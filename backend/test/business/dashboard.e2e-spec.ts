import request from "supertest";
import { createHarness, signupAndCreateBusiness, uniquePhone, type Harness } from "../harness.js";

describe("Dashboard (e2e)", () => {
  let h: Harness;
  let server: any;

  const userA = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Gérante Dash A" };
  const userB = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Gérant Dash B" };

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

  it("builds a full day of activity for business A", async () => {
    a = await signupLoginAndCreateBusiness(userA, "Boutique Dashboard A");
    b = await signupLoginAndCreateBusiness(userB, "Boutique Dashboard B");

    const product1 = await request(server)
      .post("/api/v1/products")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        name: "Produit Populaire",
        purchasePrice: 3000,
        salePrice: 5000,
        initialStock: 50,
        lowStockThreshold: 10,
      })
      .expect(201);

    const product2 = await request(server)
      .post("/api/v1/products")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        name: "Produit Rare",
        purchasePrice: 2000,
        salePrice: 8000,
        initialStock: 5,
        lowStockThreshold: 100,
      })
      .expect(201);

    const customer = await request(server)
      .post("/api/v1/customers")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ fullName: "Client Dashboard" })
      .expect(201);
    customerId = customer.body.id;

    // Sale 1: fully paid, no customer.
    await request(server)
      .post("/api/v1/sales")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        items: [{ productId: product1.body.id, quantity: 2 }],
        payments: [{ method: "cash", amount: 10000 }],
      })
      .expect(201);

    // Sale 2: underpaid, tied to the customer -> auto-credit of 5000, no due date.
    await request(server)
      .post("/api/v1/sales")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        items: [{ productId: product2.body.id, quantity: 1 }],
        payments: [{ method: "cash", amount: 3000 }],
        customerId: customer.body.id,
      })
      .expect(201);

    // A manual, overdue credit.
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    await request(server)
      .post(`/api/v1/customers/${customer.body.id}/credits`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ amount: 20000, dueDate: yesterday, note: "Ancienne dette" })
      .expect(201);

    // An expense today.
    await request(server)
      .post("/api/v1/expenses")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ category: "transport", amount: 5000 })
      .expect(201);
  });

  it("computes today's summary correctly", async () => {
    const res = await request(server)
      .get("/api/v1/dashboard/summary?period=today")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);

    expect(res.body.revenue).toBe(18000);
    expect(res.body.cogs).toBe(8000);
    expect(res.body.expensesTotal).toBe(5000);
    expect(res.body.profit).toBe(5000);
    expect(res.body.ordersCount).toBe(2);
    expect(res.body.lowStockCount).toBe(1);
    expect(res.body.outstandingCredits).toBe(25000);
    expect(res.body.overdueCreditsCount).toBe(1);
  });

  it("does not count a credit due today as overdue", async () => {
    const today = new Date().toISOString().slice(0, 10);
    await request(server)
      .post(`/api/v1/customers/${customerId}/credits`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ amount: 7000, dueDate: today })
      .expect(201);

    const res = await request(server)
      .get("/api/v1/dashboard/summary?period=today")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);

    expect(res.body.outstandingCredits).toBe(32000); // 25000 + 7000 now owed
    expect(res.body.overdueCreditsCount).toBe(1); // still only the one due yesterday
  });

  it("shows an isolated, empty summary for business B", async () => {
    const res = await request(server)
      .get("/api/v1/dashboard/summary?period=today")
      .set("Authorization", `Bearer ${b.accessToken}`)
      .expect(200);

    expect(res.body.revenue).toBe(0);
    expect(res.body.ordersCount).toBe(0);
    expect(res.body.outstandingCredits).toBe(0);
  });

  it("includes today's revenue in the 7-day sales chart", async () => {
    const res = await request(server)
      .get("/api/v1/dashboard/sales-chart?days=7")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);

    expect(res.body).toHaveLength(7);
    const today = new Date().toISOString().slice(0, 10);
    const todayBucket = res.body.find((b: { date: string }) => b.date === today);
    expect(todayBucket.revenue).toBe(18000);
  });

  it("ranks products by revenue", async () => {
    const res = await request(server)
      .get("/api/v1/dashboard/top-products?period=today")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);

    expect(res.body).toHaveLength(2);
    expect(res.body[0].name).toBe("Produit Populaire");
    expect(res.body[0].revenue).toBe(10000);
    expect(res.body[1].revenue).toBe(8000);
  });

  it("rejects period=custom without from/to", async () => {
    await request(server)
      .get("/api/v1/dashboard/summary?period=custom")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(400);
  });
});
