import request from "supertest";
import { createHarness, signupAndCreateBusiness, uniquePhone, type Harness } from "../harness.js";

describe("Customers / Credits / Expenses (e2e)", () => {
  let h: Harness;
  let server: any;

  const userA = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Gérante A" };
  const userB = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Gérant B" };

  const signupLoginAndCreateBusiness = (user: { phone: string }, businessName: string) =>
    signupAndCreateBusiness(h, user, businessName);

  beforeAll(async () => {
    h = await createHarness();
    server = h.server;
  });

  afterAll(async () => {
    await h.close();
  });

  let a: Awaited<ReturnType<typeof signupLoginAndCreateBusiness>>;
  let b: Awaited<ReturnType<typeof signupLoginAndCreateBusiness>>;
  let customerId: string;

  it("sets up two businesses", async () => {
    a = await signupLoginAndCreateBusiness(userA, "Boutique Crédit A");
    b = await signupLoginAndCreateBusiness(userB, "Boutique Crédit B");
  });

  it("creates a customer", async () => {
    const res = await request(server)
      .post("/api/v1/customers")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ fullName: "Mamadou Diallo", phone: uniquePhone() })
      .expect(201);
    customerId = res.body.id;
    expect(Number(res.body.currentBalance)).toBe(0);
  });

  it("grants a manual credit and increases the customer balance", async () => {
    const res = await request(server)
      .post(`/api/v1/customers/${customerId}/credits`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ amount: 350000, dueDate: "2026-09-20", note: "Achat divers" })
      .expect(201);
    expect(Number(res.body.remainingAmount)).toBe(350000);
    expect(res.body.status).toBe("open");

    const customer = await request(server)
      .get(`/api/v1/customers/${customerId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(customer.body.currentBalance)).toBe(350000);
  });

  it("rejects a credit payment larger than the outstanding debt", async () => {
    await request(server)
      .post(`/api/v1/customers/${customerId}/credit-payments`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ amount: 400000, method: "cash" })
      .expect(400);
  });

  it("applies a partial credit payment (FIFO)", async () => {
    await request(server)
      .post(`/api/v1/customers/${customerId}/credit-payments`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ amount: 100000, method: "cash" })
      .expect(201);

    const customer = await request(server)
      .get(`/api/v1/customers/${customerId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(customer.body.currentBalance)).toBe(250000);

    const credits = await request(server)
      .get(`/api/v1/customers/${customerId}/credits`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(credits.body[0].status).toBe("partially_paid");
    expect(Number(credits.body[0].remainingAmount)).toBe(250000);
  });

  it("pays off the remaining debt, marking the credit as paid", async () => {
    await request(server)
      .post(`/api/v1/customers/${customerId}/credit-payments`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ amount: 250000, method: "mobile_money" })
      .expect(201);

    const customer = await request(server)
      .get(`/api/v1/customers/${customerId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(customer.body.currentBalance)).toBe(0);

    const statement = await request(server)
      .get(`/api/v1/customers/${customerId}/statement`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(statement.body).toHaveLength(3); // 1 credit + 2 payments
  });

  describe("credit sale through POS", () => {
    let productId: string;
    let saleId: string;

    it("creates a product and checks out an underpaid sale tied to the customer", async () => {
      const product = await request(server)
        .post("/api/v1/products")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ name: "Sac de ciment", purchasePrice: 60000, salePrice: 90000, initialStock: 10 })
        .expect(201);
      productId = product.body.id;

      const sale = await request(server)
        .post("/api/v1/sales")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({
          items: [{ productId, quantity: 1 }],
          payments: [{ method: "cash", amount: 40000 }],
          customerId,
        })
        .expect(201);

      saleId = sale.body.id;
      expect(sale.body.amountDue).toBe("50000");

      const customer = await request(server)
        .get(`/api/v1/customers/${customerId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(Number(customer.body.currentBalance)).toBe(50000);
    });

    it("voiding the credit sale cancels the associated debt and restores stock", async () => {
      await request(server)
        .post(`/api/v1/sales/${saleId}/void`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(201);

      const customer = await request(server)
        .get(`/api/v1/customers/${customerId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(Number(customer.body.currentBalance)).toBe(0);

      const product = await request(server)
        .get(`/api/v1/products/${productId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(Number(product.body.currentStock)).toBe(10);
    });
  });

  describe("expenses", () => {
    let expenseId: string;

    it("creates and lists an expense", async () => {
      const res = await request(server)
        .post("/api/v1/expenses")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ category: "transport", amount: 15000, description: "Livraison" })
        .expect(201);
      expenseId = res.body.id;

      const list = await request(server)
        .get("/api/v1/expenses")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(list.body.total).toBeGreaterThanOrEqual(1);
    });

    it("reports the total of the whole filtered period, not just the returned page", async () => {
      await request(server)
        .post("/api/v1/expenses")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ category: "loyer", amount: 5000 })
        .expect(201);

      const firstPage = await request(server)
        .get("/api/v1/expenses?page=1&pageSize=1")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);

      expect(firstPage.body.items).toHaveLength(1);
      expect(firstPage.body.total).toBe(2);
      expect(firstPage.body.totalAmount).toBe(20000); // 15000 + 5000

      const empty = await request(server)
        .get("/api/v1/expenses?from=2020-01-01&to=2020-01-02")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(empty.body.totalAmount).toBe(0);
    });

    it("updates and deletes the expense", async () => {
      await request(server)
        .patch(`/api/v1/expenses/${expenseId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ amount: 20000 })
        .expect(200);

      await request(server)
        .delete(`/api/v1/expenses/${expenseId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);

      await request(server)
        .get(`/api/v1/expenses/${expenseId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(404);
    });
  });

  describe("credits overview", () => {
    it("lists only credits still owed, earliest due date first, undated last", async () => {
      const customer = await request(server)
        .post("/api/v1/customers")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .send({ fullName: "Client Créances" })
        .expect(201);

      const grant = async (amount: number, dueDate?: string) => {
        const res = await request(server)
          .post(`/api/v1/customers/${customer.body.id}/credits`)
          .set("Authorization", `Bearer ${a.accessToken}`)
          .send({ amount, ...(dueDate ? { dueDate } : {}) })
          .expect(201);
        return res.body.id as string;
      };
      const undated = await grant(5000);
      const later = await grant(10000, "2026-10-30");
      const sooner = await grant(20000, "2026-10-01");

      const res = await request(server)
        .get("/api/v1/credits?status=outstanding&pageSize=100")
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);

      // Fully repaid / voided credits of the earlier tests must not show up.
      expect(
        res.body.items.every((c: { status: string }) =>
          ["open", "partially_paid"].includes(c.status),
        ),
      ).toBe(true);

      const mine = res.body.items
        .filter((c: { customerId: string }) => c.customerId === customer.body.id)
        .map((c: { id: string }) => c.id);
      expect(mine).toEqual([sooner, later, undated]);
    });
  });

  describe("cross-tenant isolation", () => {
    it("business B cannot read business A's customer", async () => {
      await request(server)
        .get(`/api/v1/customers/${customerId}`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .expect(404);
    });

    it("business B cannot grant credit or record payments against business A's customer", async () => {
      await request(server)
        .post(`/api/v1/customers/${customerId}/credits`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .send({ amount: 10000 })
        .expect(404);

      await request(server)
        .post(`/api/v1/customers/${customerId}/credit-payments`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .send({ amount: 1000, method: "cash" })
        .expect(404);
    });
  });
});
