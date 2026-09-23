import request from "supertest";
import {
  addMemberSql,
  createHarness,
  loginWithOtp,
  signupAndCreateBusiness,
  uniquePhone,
  type Harness,
} from "../harness.js";

describe("Products / Categories / Inventory (e2e)", () => {
  let h: Harness;
  let server: any;

  const userA = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Commerçante A" };
  const userB = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Commerçant B" };

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
  let categoryAId: string;
  let productAId: string;

  it("sets up two independent businesses (A and B)", async () => {
    a = await signupLoginAndCreateBusiness(userA, "Boutique A");
    b = await signupLoginAndCreateBusiness(userB, "Boutique B");
    expect(a.businessId).not.toBe(b.businessId);
  });

  it("rejects business-scoped routes when the token has no active business", async () => {
    await request(server)
      .get("/api/v1/products")
      .set("Authorization", `Bearer ${a.noBusinessToken}`)
      .expect(403);
  });

  it("creates a category for business A", async () => {
    const res = await request(server)
      .post("/api/v1/categories")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ name: "Boissons" })
      .expect(201);
    categoryAId = res.body.id;
    expect(res.body.name).toBe("Boissons");
  });

  it('creates a product with initial stock, crediting an "initial" inventory movement', async () => {
    const res = await request(server)
      .post("/api/v1/products")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({
        name: "Eau minérale 1.5L",
        categoryId: categoryAId,
        purchasePrice: 3000,
        salePrice: 5000,
        initialStock: 20,
        lowStockThreshold: 5,
      })
      .expect(201);

    productAId = res.body.id;
    expect(Number(res.body.currentStock)).toBe(20);

    const movements = await request(server)
      .get(`/api/v1/inventory/movements?productId=${productAId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(movements.body.total).toBe(1);
    expect(movements.body.items[0].type).toBe("initial");
  });

  it("increases stock on a purchase_in movement and decreases it on adjustment_out", async () => {
    const afterPurchase = await request(server)
      .post("/api/v1/inventory/movements")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ productId: productAId, type: "purchase_in", quantity: 10, unitCost: 3000 })
      .expect(201);
    expect(afterPurchase.body.type).toBe("purchase_in");

    const productAfterPurchase = await request(server)
      .get(`/api/v1/products/${productAId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(productAfterPurchase.body.currentStock)).toBe(30);

    await request(server)
      .post("/api/v1/inventory/movements")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ productId: productAId, type: "adjustment_out", quantity: 4, note: "Casse" })
      .expect(201);

    const productAfterAdjustment = await request(server)
      .get(`/api/v1/products/${productAId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(Number(productAfterAdjustment.body.currentStock)).toBe(26);
  });

  it("rejects a movement that would push stock negative", async () => {
    await request(server)
      .post("/api/v1/inventory/movements")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ productId: productAId, type: "adjustment_out", quantity: 999 })
      .expect(400);
  });

  it("lists the product under /products/low-stock once stock drops to/below its threshold", async () => {
    await request(server)
      .post("/api/v1/inventory/movements")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ productId: productAId, type: "adjustment_out", quantity: 22 })
      .expect(201);

    const lowStock = await request(server)
      .get("/api/v1/products/low-stock")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(lowStock.body.some((p: { id: string }) => p.id === productAId)).toBe(true);
  });

  it("includes the product name in stock movements", async () => {
    const movements = await request(server)
      .get(`/api/v1/inventory/movements?productId=${productAId}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(movements.body.items[0].product.name).toBe("Eau minérale 1.5L");
  });

  it("deactivates a product, lists it only with isActive=false, and reactivates it", async () => {
    const extra = await request(server)
      .post("/api/v1/products")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ name: "Produit temporaire", salePrice: 1000 })
      .expect(201);

    await request(server)
      .delete(`/api/v1/products/${extra.body.id}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);

    const activeList = await request(server)
      .get("/api/v1/products?search=temporaire")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(activeList.body.total).toBe(0);

    const inactiveList = await request(server)
      .get("/api/v1/products?search=temporaire&isActive=false")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(inactiveList.body.total).toBe(1);

    await request(server)
      .patch(`/api/v1/products/${extra.body.id}`)
      .set("Authorization", `Bearer ${a.accessToken}`)
      .send({ isActive: true })
      .expect(200);

    const reactivated = await request(server)
      .get("/api/v1/products?search=temporaire")
      .set("Authorization", `Bearer ${a.accessToken}`)
      .expect(200);
    expect(reactivated.body.total).toBe(1);
  });

  describe("cross-tenant isolation", () => {
    it("business B cannot read business A's category", async () => {
      await request(server)
        .get(`/api/v1/categories/${categoryAId}`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .expect(404);
    });

    it("business B cannot read, update, or delete business A's product", async () => {
      await request(server)
        .get(`/api/v1/products/${productAId}`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .expect(404);

      await request(server)
        .patch(`/api/v1/products/${productAId}`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .send({ name: "Piraté" })
        .expect(404);

      await request(server)
        .delete(`/api/v1/products/${productAId}`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .expect(404);
    });

    it("business B cannot record an inventory movement against business A's product", async () => {
      await request(server)
        .post("/api/v1/inventory/movements")
        .set("Authorization", `Bearer ${b.accessToken}`)
        .send({ productId: productAId, type: "purchase_in", quantity: 5 })
        .expect(404);
    });

    it("business A's product was never actually modified by B's attempts", async () => {
      const res = await request(server)
        .get(`/api/v1/products/${productAId}`)
        .set("Authorization", `Bearer ${a.accessToken}`)
        .expect(200);
      expect(res.body.name).toBe("Eau minérale 1.5L");
    });
  });
});
