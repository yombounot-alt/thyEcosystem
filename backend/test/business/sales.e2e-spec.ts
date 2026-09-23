import request from "supertest";
import {
  addMemberSql,
  createHarness,
  loginWithOtp,
  signupAndCreateBusiness,
  uniquePhone,
  type Harness,
} from "../harness.js";

describe("Sales / POS (e2e)", () => {
  let h: Harness;
  let server: any;

  const userA = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Vendeuse A" };
  const userB = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Vendeur B" };

  const signupLoginAndCreateBusiness = (user: { phone: string }, businessName: string) =>
    signupAndCreateBusiness(h, user, businessName);

  async function createProduct(token: string, name: string, salePrice: number, stock: number) {
    const res = await request(server)
      .post("/api/v1/products")
      .set("Authorization", `Bearer ${token}`)
      .send({ name, purchasePrice: Math.round(salePrice * 0.6), salePrice, initialStock: stock })
      .expect(201);
    return res.body.id as string;
  }

  beforeAll(async () => {
    h = await createHarness();
    server = h.server;
  });

  afterAll(async () => {
    await h.close();
  });

  let a: Awaited<ReturnType<typeof signupLoginAndCreateBusiness>>;
  let b: Awaited<ReturnType<typeof signupLoginAndCreateBusiness>>;
  let waterId: string;
  let riceId: string;
  let saleId: string;

  it("sets up two businesses with products", async () => {
    a = await signupLoginAndCreateBusiness(userA, "Boutique Vente A");
    b = await signupLoginAndCreateBusiness(userB, "Boutique Vente B");
    waterId = await createProduct(a.accessToken, "Eau minérale 1.5L", 5000, 20);
    riceId = await createProduct(a.accessToken, "Riz local 25kg", 220000, 5);
  });

  it("rejects checkout when payment does not cover the total", async () => {
    await request(server)
      .post("/api/v1/sales")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        items: [{ productId: waterId, quantity: 2 }],
        payments: [{ method: "cash", amount: 5000 }],
      })
      .expect(400);
  });

  it("rejects checkout that would oversell a product, without side effects", async () => {
    await request(server)
      .post("/api/v1/sales")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        items: [{ productId: riceId, quantity: 999 }],
        payments: [{ method: "cash", amount: 999 * 220000 }],
      })
      .expect(400);

    const product = await request(server)
      .get(`/api/v1/products/${riceId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(product.body.currentStock)).toBe(5);
  });

  it("checks out a sale with a discount, decrementing stock and computing totals correctly", async () => {
    const res = await request(server)
      .post("/api/v1/sales")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        items: [
          { productId: waterId, quantity: 2 },
          { productId: riceId, quantity: 1 },
        ],
        payments: [{ method: "cash", amount: 225000 }],
        discountTotal: 5000,
      })
      .expect(201);

    saleId = res.body.id;
    expect(res.body.subtotal).toBe("230000");
    expect(res.body.discountTotal).toBe("5000");
    expect(res.body.total).toBe("225000");
    expect(res.body.amountDue).toBe("0");
    expect(res.body.saleNumber).toBe("VTE-0001");
    expect(res.body.items).toHaveLength(2);

    const water = await request(server)
      .get(`/api/v1/products/${waterId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(water.body.currentStock)).toBe(18);

    const rice = await request(server)
      .get(`/api/v1/products/${riceId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(rice.body.currentStock)).toBe(4);

    const movements = await request(server)
      .get(`/api/v1/inventory/movements?productId=${waterId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(movements.body.items.some((m: { type: string }) => m.type === "sale_out")).toBe(true);
  });

  it("voids the sale, restoring stock", async () => {
    await request(server)
      .post(`/api/v1/sales/${saleId}/void`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(201);

    const water = await request(server)
      .get(`/api/v1/products/${waterId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(water.body.currentStock)).toBe(20);

    const sale = await request(server)
      .get(`/api/v1/sales/${saleId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(sale.body.status).toBe("void");
  });

  it("rejects voiding an already-void sale", async () => {
    await request(server)
      .post(`/api/v1/sales/${saleId}/void`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(400);
  });

  describe("idempotency and credit sales", () => {
    it("replaying a checkout with the same clientRequestId returns the same sale and sells once", async () => {
      const body = {
        items: [{ productId: waterId, quantity: 3 }],
        payments: [{ method: "cash", amount: 15000 }],
        clientRequestId: "req-idempotent-0001",
      };

      const first = await request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send(body)
        .expect(201);
      const second = await request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send(body)
        .expect(201);

      expect(second.body.id).toBe(first.body.id);
      expect(second.body.saleNumber).toBe(first.body.saleNumber);

      const water = await request(server)
        .get(`/api/v1/products/${waterId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(Number(water.body.currentStock)).toBe(17);
    });

    it("sells only once when the same request arrives twice at the same time", async () => {
      const body = {
        items: [{ productId: waterId, quantity: 1 }],
        payments: [{ method: "cash", amount: 5000 }],
        clientRequestId: "req-concurrent-0001",
      };
      const send = () =>
        request(server)
          .post("/api/v1/sales")
          .set("Authorization", `Bearer ${a.accessToken}`)
          .send(body);

      const [first, second] = await Promise.all([send(), send()]);

      expect([first.status, second.status]).toEqual([201, 201]);
      expect(first.body.id).toBe(second.body.id);

      const water = await request(server)
        .get(`/api/v1/products/${waterId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(Number(water.body.currentStock)).toBe(16);
    });

    it("rejects a sale with no payment and no customer", async () => {
      await request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ items: [{ productId: waterId, quantity: 1 }] })
        .expect(400);
    });

    it("sells fully on credit to a customer, with no payment at all", async () => {
      const customer = await request(server)
        .post("/api/v1/customers")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ fullName: "Mamadou Diallo" })
        .expect(201);

      const sale = await request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ items: [{ productId: waterId, quantity: 2 }], customerId: customer.body.id })
        .expect(201);

      expect(sale.body.total).toBe("10000");
      expect(sale.body.amountPaid).toBe("0");
      expect(sale.body.amountDue).toBe("10000");
      expect(sale.body.payments).toEqual([]);
      expect(sale.body.customer.fullName).toBe("Mamadou Diallo");

      const detail = await request(server)
        .get(`/api/v1/sales/${sale.body.id}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(detail.body.customer.fullName).toBe("Mamadou Diallo");

      const updated = await request(server)
        .get(`/api/v1/customers/${customer.body.id}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(Number(updated.body.currentBalance)).toBe(10000);
    });
  });

  describe("sales rung up offline and synced later", () => {
    const hoursAgo = (h: number) => new Date(Date.now() - h * 3600 * 1000);
    const daysAgo = (d: number) => new Date(Date.now() - d * 24 * 3600 * 1000);
    let soapId: string;

    const offlineSale = (body: Record<string, unknown>) =>
      request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ offline: true, ...body });

    const stockOf = async (productId: string) => {
      const res = await request(server)
        .get(`/api/v1/products/${productId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      return Number(res.body.currentStock);
    };

    beforeAll(async () => {
      soapId = await createProduct(a.accessToken, "Savon offline", 2500, 3);
    });

    it("keeps the real date of the sale, on the sale and on its stock movement", async () => {
      const soldAt = hoursAgo(5);
      const res = await offlineSale({
        items: [{ productId: soapId, quantity: 1 }],
        payments: [{ method: "cash", amount: 2500 }],
        soldAt: soldAt.toISOString(),
        clientRequestId: "offline-date-0001",
      }).expect(201);

      expect(new Date(res.body.soldAt).getTime()).toBe(soldAt.getTime());

      const movements = await request(server)
        .get(`/api/v1/inventory/movements?productId=${soapId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      const saleOut = movements.body.items.find((m: any) => m.type === "sale_out");
      expect(new Date(saleOut.createdAt).getTime()).toBe(soldAt.getTime());

      // It shows up in the period it really belongs to.
      const from = hoursAgo(6).toISOString();
      const to = hoursAgo(4).toISOString();
      const list = await request(server)
        .get(`/api/v1/sales?from=${from}&to=${to}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(list.body.items.map((s: any) => s.id)).toContain(res.body.id);
    });

    it("brings a date in the future back to now instead of refusing the sale", async () => {
      const before = Date.now();
      const res = await offlineSale({
        items: [{ productId: soapId, quantity: 1 }],
        payments: [{ method: "cash", amount: 2500 }],
        soldAt: new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString(),
      }).expect(201);

      const soldAt = new Date(res.body.soldAt).getTime();
      expect(soldAt).toBeGreaterThanOrEqual(before - 1000);
      expect(soldAt).toBeLessThanOrEqual(Date.now() + 1000);
    });

    it("refuses a sale dated more than 60 days ago, without side effects", async () => {
      const stockBefore = await stockOf(soapId);
      await offlineSale({
        items: [{ productId: soapId, quantity: 1 }],
        payments: [{ method: "cash", amount: 2500 }],
        soldAt: daysAgo(61).toISOString(),
      }).expect(400);
      expect(await stockOf(soapId)).toBe(stockBefore);
    });

    it("records an offline sale even when the stock is no longer sufficient (goods already left)", async () => {
      const stock = await stockOf(soapId);
      const body = {
        items: [{ productId: soapId, quantity: stock + 4 }],
        payments: [{ method: "cash", amount: (stock + 4) * 2500 }],
      };

      // The same sale rung up online is refused…
      await request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send(body)
        .expect(400);
      expect(await stockOf(soapId)).toBe(stock);

      // …but offline it already happened, so the stock goes negative to flag the gap.
      await offlineSale(body).expect(201);
      expect(await stockOf(soapId)).toBe(-4);
    });

    it("records an offline sale of a product deactivated in the meantime", async () => {
      const gone = await createProduct(a.accessToken, "Produit retiré", 1000, 5);
      await request(server)
        .delete(`/api/v1/products/${gone}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);

      const sale = {
        items: [{ productId: gone, quantity: 1 }],
        payments: [{ method: "cash", amount: 1000 }],
      };
      await request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send(sale)
        .expect(400);
      await offlineSale(sale).expect(201);
      expect(await stockOf(gone)).toBe(4);
    });

    it("is still idempotent: replaying an offline sale returns the original", async () => {
      const body = {
        items: [{ productId: waterId, quantity: 1 }],
        payments: [{ method: "cash", amount: 5000 }],
        soldAt: hoursAgo(2).toISOString(),
        clientRequestId: "offline-replay-0001",
      };
      const stockBefore = await stockOf(waterId);

      const first = await offlineSale(body).expect(201);
      const replay = await offlineSale(body).expect(201);

      expect(replay.body.id).toBe(first.body.id);
      expect(await stockOf(waterId)).toBe(stockBefore - 1);
    });

    it("never lets the offline flag reach another business's products", async () => {
      const foreign = await createProduct(b.accessToken, "Produit de B", 1000, 5);
      await offlineSale({
        items: [{ productId: foreign, quantity: 1 }],
        payments: [{ method: "cash", amount: 1000 }],
      }).expect(404);
    });

    it("rejects a malformed date", async () => {
      await offlineSale({
        items: [{ productId: soapId, quantity: 1 }],
        payments: [{ method: "cash", amount: 2500 }],
        soldAt: "hier soir",
      }).expect(400);
    });
  });

  describe("cross-tenant isolation", () => {
    it("business B cannot read or void business A's sale", async () => {
      await request(server)
        .get(`/api/v1/sales/${saleId}`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .expect(404);

      await request(server)
        .post(`/api/v1/sales/${saleId}/void`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .expect(404);
    });

    it("business B cannot checkout against business A's product", async () => {
      await request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${b.accessToken}`)
        .send({
          items: [{ productId: waterId, quantity: 1 }],
          payments: [{ method: "cash", amount: 5000 }],
        })
        .expect(404);
    });
  });
});
