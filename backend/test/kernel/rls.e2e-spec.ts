import request from "supertest";
import type pg from "pg";
import {
  API,
  createBusiness,
  createHarness,
  loginWithOtp,
  uniquePhone,
  type Harness,
} from "../harness.js";

/**
 * L'isolation entre entreprises est garantie par la BASE (RLS forcée), pas seulement par le code :
 * ces tests interrogent PostgreSQL directement, sous le rôle applicatif `thy_app`, sans passer par
 * l'API — un oubli de `WHERE business_id = …` dans un service ne doit jamais pouvoir fuiter.
 */
describe("Row-Level Security — isolation garantie par PostgreSQL (e2e)", () => {
  let h: Harness;
  let bizA: string;
  let bizB: string;
  let productA: string;

  beforeAll(async () => {
    h = await createHarness();
    const a = await createBusiness(h, await loginWithOtp(h, uniquePhone()), "RLS A");
    const b = await createBusiness(h, await loginWithOtp(h, uniquePhone()), "RLS B");
    bizA = a.businessId;
    bizB = b.businessId;

    const product = await request(h.server)
      .post(`${API}/products`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ name: "Produit RLS", salePrice: 1000, initialStock: 5 })
      .expect(201);
    productA = product.body.id;
    await request(h.server)
      .post(`${API}/sales`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        items: [{ productId: productA, quantity: 1 }],
        payments: [{ method: "cash", amount: 1000 }],
      })
      .expect(201);
  });
  afterAll(async () => {
    await h.close();
  });

  /** Exécute `fn` dans une transaction annulée, sous le rôle thy_app, avec l'entreprise donnée. */
  async function asApp<T>(
    context: { businessId?: string; userId?: string },
    fn: (c: pg.PoolClient) => Promise<T>,
  ): Promise<T> {
    const client = await h.sql.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL ROLE thy_app");
      if (context.businessId)
        await client.query("SELECT set_config('app.business_id', $1, true)", [context.businessId]);
      if (context.userId)
        await client.query("SELECT set_config('app.user_id', $1, true)", [context.userId]);
      return await fn(client);
    } finally {
      await client.query("ROLLBACK");
      client.release();
    }
  }

  const count = async (c: pg.PoolClient, table: string) =>
    Number((await c.query(`SELECT count(*) FROM ${table}`)).rows[0].count);

  it("le rôle applicatif ne contourne pas la RLS", async () => {
    const role = await h.sql.query(
      "SELECT rolbypassrls, rolsuper FROM pg_roles WHERE rolname = 'thy_app'",
    );
    expect(role.rows[0]).toEqual({ rolbypassrls: false, rolsuper: false });
  });

  it("toutes les tables du schéma biz ont la RLS activée ET forcée", async () => {
    const res = await h.sql.query(
      `SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'biz' AND c.relkind = 'r' AND NOT (c.relrowsecurity AND c.relforcerowsecurity)`,
    );
    expect(res.rows).toEqual([]);
  });

  it("sans contexte d'entreprise, aucune ligne n'est visible (fail-closed)", async () => {
    await asApp({}, async (c) => {
      for (const table of [
        "products",
        "sales",
        "sale_items",
        "payments",
        "inventory_movements",
        "customers",
      ])
        expect(await count(c, `biz.${table}`), table).toBe(0);
      expect(await count(c, "core.business_members")).toBe(0);
    });
  });

  it("avec le contexte de l'entreprise A, on voit A et jamais B", async () => {
    await asApp({ businessId: bizA }, async (c) => {
      expect(await count(c, "biz.products")).toBeGreaterThanOrEqual(1);
      const foreign = await c.query("SELECT count(*) FROM biz.products WHERE business_id <> $1", [
        bizA,
      ]);
      expect(Number(foreign.rows[0].count)).toBe(0);
      const sales = await c.query("SELECT count(*) FROM biz.sales WHERE business_id <> $1", [bizA]);
      expect(Number(sales.rows[0].count)).toBe(0);
    });
  });

  it("avec le contexte de B, les données de A sont invisibles et inaltérables", async () => {
    await asApp({ businessId: bizB }, async (c) => {
      expect(await count(c, "biz.products")).toBe(0);
      expect((await c.query("UPDATE biz.products SET name = 'piraté'")).rowCount).toBe(0);
      expect((await c.query("DELETE FROM biz.sales")).rowCount).toBe(0);
      const byId = await c.query("SELECT 1 FROM biz.products WHERE id = $1", [productA]);
      expect(byId.rowCount).toBe(0);
    });
  });

  it("on ne peut pas écrire dans une autre entreprise que celle du contexte", async () => {
    await asApp({ businessId: bizA }, async (c) => {
      await expect(
        c.query(
          "INSERT INTO biz.products (business_id, name, sale_price) VALUES ($1, 'intrus', 1)",
          [bizB],
        ),
      ).rejects.toThrow(/row-level security/);
    });
  });

  it("une clé étrangère composite interdit de rattacher une ligne à l'objet d'une autre entreprise", async () => {
    await asApp({ businessId: bizB }, async (c) => {
      // Contexte B, mais la ligne pointe vers le produit de A : la FK (business_id, id) échoue.
      await expect(
        c.query(
          `INSERT INTO biz.inventory_movements (business_id, product_id, type, quantity, created_by)
           VALUES ($1, $2, 'purchase_in', 1, (SELECT id FROM core.users LIMIT 1))`,
          [bizB, productA],
        ),
      ).rejects.toThrow(/violates foreign key constraint/);
    });
  });

  it("le journal des mouvements de stock est en ajout seul (ni UPDATE ni DELETE pour thy_app)", async () => {
    await asApp({ businessId: bizA }, async (c) => {
      await c.query("SAVEPOINT s1");
      await expect(c.query("UPDATE biz.inventory_movements SET note = 'x'")).rejects.toThrow(
        /permission denied/,
      );
      await c.query("ROLLBACK TO SAVEPOINT s1");
      await expect(c.query("DELETE FROM biz.inventory_movements")).rejects.toThrow(
        /permission denied/,
      );
    });
  });

  it("un utilisateur ne voit que ses propres adhésions, jamais celles des autres entreprises", async () => {
    const owner = await h.sql.query("SELECT owner_id FROM core.businesses WHERE id = $1", [bizA]);
    const userA = owner.rows[0].owner_id as string;
    await asApp({ userId: userA }, async (c) => {
      const rows = await c.query("SELECT DISTINCT user_id FROM core.business_members");
      expect(rows.rows.every((r: { user_id: string }) => r.user_id === userA)).toBe(true);
      const businesses = await c.query("SELECT id FROM core.businesses");
      expect(businesses.rows.map((r: { id: string }) => r.id)).not.toContain(bizB);
    });
  });
});
