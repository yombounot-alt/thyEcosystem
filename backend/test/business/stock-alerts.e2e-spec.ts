import request from "supertest";
import {
  API,
  addMemberSql,
  createHarness,
  loginWithOtp,
  signupAndCreateBusiness,
  uniquePhone,
  type Harness,
} from "../harness.js";

const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });

/**
 * Stock : exactitude en concurrence, ventes hors ligne tracées, et alertes (seuil, stock négatif)
 * envoyées aux responsables du stock via l'outbox.
 */
describe("Stock — concurrence, ventes hors ligne et alertes (e2e)", () => {
  let h: Harness;
  let owner: Awaited<ReturnType<typeof signupAndCreateBusiness>>;

  const createProduct = async (body: Record<string, unknown>) =>
    (
      await request(h.server)
        .post(`${API}/products`)
        .set(bearer(owner.accessToken))
        .send({ salePrice: 1000, ...body })
        .expect(201)
    ).body as { id: string };
  const stockOf = async (id: string) =>
    Number(
      (await request(h.server).get(`${API}/products/${id}`).set(bearer(owner.accessToken))).body
        .currentStock,
    );
  const sell = (productId: string, quantity: number, extra: Record<string, unknown> = {}) =>
    request(h.server)
      .post(`${API}/sales`)
      .set(bearer(owner.accessToken))
      .send({
        items: [{ productId, quantity }],
        payments: [{ method: "cash", amount: 1000 * quantity }],
        ...extra,
      });
  const typesFor = async (userId: string) =>
    (
      await h.sql.query<{ type: string; body: string }>(
        "SELECT type, body FROM ntf.notifications WHERE user_id = $1 ORDER BY created_at",
        [userId],
      )
    ).rows;

  beforeAll(async () => {
    h = await createHarness();
    await h.skipOutboxBacklog();
    owner = await signupAndCreateBusiness(h, { phone: uniquePhone() }, "Stock & Co");
  });
  afterAll(async () => {
    await h.close();
  });

  it("des ventes simultanées décrémentent toutes le stock, sans jamais vendre plus que disponible", async () => {
    const p = await createProduct({ name: "Riz 25 kg", initialStock: 5 });
    const results = await Promise.all(Array.from({ length: 8 }, () => sell(p.id, 1)));
    const ok = results.filter((r) => r.status === 201).length;
    const refused = results.filter((r) => r.status === 400).length;
    expect(ok).toBe(5);
    expect(refused).toBe(3);
    expect(await stockOf(p.id)).toBe(0);
  });

  it("plusieurs caisses encaissent en même temps : numéros de vente uniques et consécutifs", async () => {
    const p = await createProduct({ name: "Sucre", initialStock: 100 });
    const results = await Promise.all(Array.from({ length: 10 }, () => sell(p.id, 1)));
    expect(results.map((r) => r.status)).toEqual(Array(10).fill(201));
    const numbers = results
      .map((r) => Number(String(r.body.saleNumber).slice(4)))
      .sort((a, b) => a - b);
    expect(new Set(numbers).size).toBe(10);
    expect(numbers.at(-1)! - numbers[0]!).toBe(9);
  });

  it("franchir le seuil d'alerte prévient les responsables du stock — une seule fois", async () => {
    const keeper = await loginWithOtp(h, uniquePhone());
    const cashier = await loginWithOtp(h, uniquePhone());
    await addMemberSql(h, owner.businessId, keeper.userId, "STOCK_KEEPER");
    await addMemberSql(h, owner.businessId, cashier.userId, "CASHIER");
    const p = await createProduct({ name: "Huile 5 L", initialStock: 5, lowStockThreshold: 2 });

    await sell(p.id, 2).expect(201); // 3 : au-dessus du seuil
    await sell(p.id, 1).expect(201); // 2 : franchit le seuil
    await sell(p.id, 1).expect(201); // 1 : déjà sous le seuil, pas de nouvelle alerte
    await h.drainOutbox();

    for (const userId of [owner.userId, keeper.userId]) {
      const low = (await typesFor(userId)).filter((n) => n.type === "STOCK_LOW");
      expect(low, userId).toHaveLength(1);
      expect(low[0]!.body).toContain("Il reste 2");
    }
    expect((await typesFor(cashier.userId)).map((n) => n.type)).not.toContain("STOCK_LOW");
  });

  it("une vente hors ligne peut passer sous zéro : elle est marquée et une alerte part", async () => {
    const p = await createProduct({ name: "Savon", initialStock: 1 });
    const res = await sell(p.id, 3, {
      offline: true,
      soldAt: new Date(Date.now() - 3600_000).toISOString(),
      clientRequestId: `offline-${Date.now()}`,
    }).expect(201);
    expect(await stockOf(p.id)).toBe(-2);
    const row = await h.sql.query("SELECT is_offline FROM biz.sales WHERE id = $1", [res.body.id]);
    expect(row.rows[0].is_offline).toBe(true);

    await h.drainOutbox();
    const neg = (await typesFor(owner.userId)).filter((n) => n.type === "STOCK_NEGATIVE");
    expect(neg).toHaveLength(1);
    expect(neg[0]!.body).toContain("-2");

    // Une vente « en ligne » reste refusée quand le stock manque.
    await sell(p.id, 1).expect(400);
  });
});
