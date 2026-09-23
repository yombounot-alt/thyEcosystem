import request from "supertest";
import {
  addMemberSql,
  createHarness,
  createBusiness,
  loginWithOtp,
  uniquePhone,
  type Harness,
} from "../harness.js";

const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(200, 7),
]);
const bigPng = (bytes: number) => Buffer.concat([PNG, Buffer.alloc(bytes)]);

describe("Direct payments: Orange Money / Mobile Money / merchant code (e2e)", () => {
  let h: Harness;
  let server: any;

  const owner = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Propriétaire A" };
  const otherOwner = {
    phone: uniquePhone(),
    password: "MotDePasse123!",
    fullName: "Propriétaire B",
  };
  const cashierUser = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Caissier" };
  const phones = [owner.phone, otherOwner.phone, cashierUser.phone];

  let a: { token: string; businessId: string; userId: string };
  let b: { token: string; businessId: string; userId: string };
  let cashier: string; // token of a member with role "cashier" in business A
  let waterId: string; // 5 000 GNF, stock 50
  let riceId: string; // 220 000 GNF, stock 5
  let oddId: string; // 2 001 GNF
  let orangeId: string;
  let momoId: string;
  let codeId: string;

  let seq = 0;
  const requestId = () => `pay-${Date.now()}-${++seq}`;
  const tx = () => `TX${Date.now()}${++seq}`.slice(0, 20);
  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  async function ownerWithBusiness(user: typeof owner, name: string) {
    const session = await loginWithOtp(h, user.phone);
    const business = await createBusiness(h, session, name);
    return { token: business.accessToken, businessId: business.businessId, userId: session.userId };
  }

  const product = async (token: string, name: string, price: number, stock: number) =>
    (
      await request(server)
        .post("/api/v1/products")
        .set(auth(token))
        .send({
          name,
          purchasePrice: Math.round(price * 0.6),
          salePrice: price,
          initialStock: stock,
        })
        .expect(201)
    ).body.id as string;

  const stockOf = async (token: string, id: string) =>
    Number(
      (await request(server).get(`/api/v1/products/${id}`).set(auth(token)).expect(200)).body
        .currentStock,
    );

  const salesCount = async (businessId: string) =>
    Number(
      (await h.sql.query("SELECT count(*) FROM biz.sales WHERE business_id = $1", [businessId]))
        .rows[0].count,
    );

  const createMethod = (token: string, body: Record<string, unknown>) =>
    request(server).post("/api/v1/payment-methods").set(auth(token)).send(body);

  const start = (token: string, body: Record<string, unknown>) =>
    request(server).post("/api/v1/payments").set(auth(token)).send(body);

  /** A payment for `qty` waters (5 000 GNF each) on the given method, not yet declared. */
  async function newPayment(qty = 2, methodId = orangeId, extra: Record<string, unknown> = {}) {
    const res = await start(a.token, {
      items: [{ productId: waterId, quantity: qty }],
      paymentMethodId: methodId,
      clientRequestId: requestId(),
      ...extra,
    }).expect(201);
    return res.body as { id: string; amount: number };
  }

  const declaration = (amount: number, extra: Record<string, unknown> = {}) => ({
    payerPhone: "655 11 22 33",
    transactionReference: tx(),
    amountSent: amount,
    payerName: "Mamadou Bah",
    ...extra,
  });

  const submit = (token: string, id: string, body: Record<string, unknown>) =>
    request(server).post(`/api/v1/payments/${id}/submit`).set(auth(token)).send(body);
  const verify = (token: string, id: string) =>
    request(server).post(`/api/v1/payments/${id}/verify`).set(auth(token));
  const reject = (token: string, id: string, body: Record<string, unknown> = {}) =>
    request(server).post(`/api/v1/payments/${id}/reject`).set(auth(token)).send(body);
  const cancel = (token: string, id: string) =>
    request(server).post(`/api/v1/payments/${id}/cancel`).set(auth(token));
  const read = (token: string, id: string) =>
    request(server).get(`/api/v1/payments/${id}`).set(auth(token));

  /** A payment the customer has declared, waiting for the owner. */
  async function submittedPayment(qty = 2, methodId = orangeId, ref = tx()) {
    const p = await newPayment(qty, methodId);
    await submit(a.token, p.id, declaration(p.amount, { transactionReference: ref })).expect(201);
    return p;
  }

  beforeAll(async () => {
    h = await createHarness();
    server = h.server;
  });

  afterAll(async () => {
    await h.close();
  });

  it("sets up two businesses, a cashier, and products", async () => {
    a = await ownerWithBusiness(owner, "Boutique Paiements A");
    b = await ownerWithBusiness(otherOwner, "Boutique Paiements B");

    // A cashier: a member of business A whose role is not "owner".
    const cashierSession = await loginWithOtp(h, cashierUser.phone);
    await addMemberSql(h, a.businessId, cashierSession.userId, "CASHIER");
    const activated = await request(server)
      .post(`/api/v1/businesses/${a.businessId}/activate`)
      .set(auth(cashierSession.accessToken))
      .expect(200);
    cashier = activated.body.accessToken;

    waterId = await product(a.token, "Eau minérale 1.5L", 5000, 50);
    riceId = await product(a.token, "Riz local 25kg", 220000, 5);
    oddId = await product(a.token, "Article à 2001", 2001, 100);
  });

  // ==========================================================================================
  describe("settings: payment methods", () => {
    it("lets the owner add Orange Money, Mobile Money and a merchant code — none exist until then", async () => {
      const empty = await request(server)
        .get("/api/v1/payment-methods")
        .set(auth(a.token))
        .expect(200);
      expect(empty.body).toEqual([]); // nothing is invented for the owner

      const orange = await createMethod(a.token, {
        provider: "orange_money",
        accountName: "Aissatou Diallo",
        phoneNumber: "622 12 34 56",
      }).expect(201);
      orangeId = orange.body.id;
      expect(orange.body).toMatchObject({
        provider: "orange_money",
        displayName: "Orange Money", // the default name of the kind
        accountName: "Aissatou Diallo",
        phoneNumber: "622 12 34 56",
        isActive: true,
        hasLogo: false,
      });
      expect(orange.body.instructionSteps).toHaveLength(8);
      expect(orange.body.instructionSteps[0]).toContain("Orange Money");

      const momo = await createMethod(a.token, {
        provider: "mobile_money",
        accountName: "Aissatou Diallo",
        phoneNumber: "666 00 00 01",
      }).expect(201);
      momoId = momo.body.id;
      expect(momo.body.displayName).toBe("Mobile Money");

      const code = await createMethod(a.token, {
        provider: "merchant_code",
        accountName: "Boutique A",
        merchantCode: "MARCHAND-77",
      }).expect(201);
      codeId = code.body.id;
      expect(code.body.displayName).toBe("Code marchand");
      expect(code.body.instructionSteps.join(" ")).toContain("code marchand");
    });

    it("refuses what does not make sense for the kind of payment", async () => {
      const bad = (body: Record<string, unknown>) => createMethod(a.token, body).expect(400);
      await bad({ provider: "orange_money" }); // a number is required
      await bad({ provider: "mobile_money", phoneNumber: "" });
      await bad({ provider: "merchant_code" }); // a code is required
      await bad({ provider: "other" }); // a number or a code
      await bad({ provider: "orange_money", phoneNumber: "abc" });
      await bad({ provider: "orange_money", phoneNumber: "12" });
      await bad({ provider: "merchant_code", merchantCode: "<script>" });
      await bad({ provider: "orange_money", phoneNumber: "622123456", ussdCode: "*144*abc#" });
      await bad({ provider: "paypal", phoneNumber: "622123456" });
      await bad({ provider: "orange_money", phoneNumber: "622123456", isAdmin: true }); // unknown field
    });

    it('accepts "other", a USSD template, custom instructions — and cleans what was typed', async () => {
      const res = await createMethod(a.token, {
        provider: "other",
        displayName: "  Wave \u0007  Guinée ",
        accountName: "  Aissatou\u0000   Diallo ",
        phoneNumber: "+224 622 123 456",
        ussdCode: "*144*1*{numero}*{montant}#",
        instructions: "  Ouvrez Wave  \n\n\n\n Envoyez le montant   \r\n",
      }).expect(201);

      expect(res.body.displayName).toBe("Wave Guinée");
      expect(res.body.accountName).toBe("Aissatou Diallo");
      expect(res.body.ussdCode).toBe("*144*1*{numero}*{montant}#");
      expect(res.body.instructionSteps).toEqual(["Ouvrez Wave", "Envoyez le montant"]);
      await request(server)
        .delete(`/api/v1/payment-methods/${res.body.id}`)
        .set(auth(a.token))
        .expect(204);
    });

    it("allows several accounts of the same operator, and the owner picks which are active", async () => {
      const second = await createMethod(a.token, {
        provider: "orange_money",
        displayName: "Orange Money 2",
        phoneNumber: "621 99 88 77",
      }).expect(201);

      const list = await request(server)
        .get("/api/v1/payment-methods")
        .set(auth(a.token))
        .expect(200);
      expect(list.body.filter((m: any) => m.provider === "orange_money")).toHaveLength(2);

      await request(server)
        .patch(`/api/v1/payment-methods/${second.body.id}`)
        .set(auth(a.token))
        .send({ isActive: false })
        .expect(200);
      // The owner still sees it (to switch it back on); a cashier is only offered the active ones.
      expect(
        (await request(server).get("/api/v1/payment-methods").set(auth(a.token)).expect(200)).body,
      ).toHaveLength(4);
      const forCashier = await request(server)
        .get("/api/v1/payment-methods")
        .set(auth(cashier))
        .expect(200);
      expect(forCashier.body.map((m: any) => m.displayName).sort()).toEqual(
        ["Code marchand", "Mobile Money", "Orange Money"].sort(),
      );
      await request(server)
        .get(`/api/v1/payment-methods/${second.body.id}`)
        .set(auth(cashier))
        .expect(404);

      await request(server)
        .delete(`/api/v1/payment-methods/${second.body.id}`)
        .set(auth(a.token))
        .expect(204);
    });

    it("updates partially, clears optional fields when sent empty, and keeps required ones", async () => {
      const res = await request(server)
        .patch(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(a.token))
        .send({ accountName: "Nouveau Titulaire", instructions: "Étape 1\nÉtape 2" })
        .expect(200);
      expect(res.body.accountName).toBe("Nouveau Titulaire");
      expect(res.body.phoneNumber).toBe("622 12 34 56"); // untouched
      expect(res.body.instructionSteps).toEqual(["Étape 1", "Étape 2"]);

      const cleared = await request(server)
        .patch(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(a.token))
        .send({ instructions: "", accountName: "Aissatou Diallo" })
        .expect(200);
      expect(cleared.body.instructions).toBeNull();
      expect(cleared.body.instructionSteps).toHaveLength(8); // back to the defaults

      await request(server)
        .patch(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(a.token))
        .send({ phoneNumber: "" })
        .expect(400);
    });

    it("is reserved to the owner for changes, readable by the team, closed to strangers", async () => {
      await createMethod(cashier, { provider: "orange_money", phoneNumber: "622111111" }).expect(
        403,
      );
      await request(server)
        .patch(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(cashier))
        .send({ isActive: false })
        .expect(403);
      await request(server)
        .delete(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(cashier))
        .expect(403);
      await request(server)
        .get(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(cashier))
        .expect(200);

      await request(server).get("/api/v1/payment-methods").expect(401);
      await request(server)
        .post("/api/v1/payment-methods")
        .send({ provider: "orange_money", phoneNumber: "622111111" })
        .expect(401);
    });

    it("keeps one business's methods invisible and untouchable for another (404, never 403)", async () => {
      expect(
        (await request(server).get("/api/v1/payment-methods").set(auth(b.token)).expect(200)).body,
      ).toEqual([]);
      await request(server)
        .get(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(b.token))
        .expect(404);
      await request(server)
        .patch(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(b.token))
        .send({ isActive: false })
        .expect(404);
      await request(server)
        .delete(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(b.token))
        .expect(404);
    });

    it("stores a logo after checking the picture itself, and serves it back", async () => {
      await request(server)
        .put(`/api/v1/payment-methods/${orangeId}/logo`)
        .set(auth(a.token))
        .attach("file", PNG, { filename: "logo.png", contentType: "image/png" })
        .expect(200)
        .expect((res) => expect(res.body.hasLogo).toBe(true));

      const logo = await request(server)
        .get(`/api/v1/payment-methods/${orangeId}/logo`)
        .set(auth(cashier))
        .expect(200);
      expect(logo.headers["content-type"]).toBe("image/png");
      expect(logo.headers["x-content-type-options"]).toBe("nosniff");
      expect(Buffer.compare(logo.body, PNG)).toBe(0);

      await request(server)
        .get(`/api/v1/payment-methods/${orangeId}/logo`)
        .set(auth(b.token))
        .expect(404);
    });

    it("refuses a fake picture, an oversized one, and a logo from a non-owner", async () => {
      await request(server)
        .put(`/api/v1/payment-methods/${momoId}/logo`)
        .set(auth(a.token))
        .attach("file", Buffer.from("<html><script>alert(1)</script></html>"), {
          filename: "logo.png",
          contentType: "image/png",
        })
        .expect(400);
      await request(server)
        .put(`/api/v1/payment-methods/${momoId}/logo`)
        .set(auth(a.token))
        .attach("file", bigPng(1024 * 1024 + 10), { filename: "big.png", contentType: "image/png" })
        .expect(413);
      await request(server)
        .put(`/api/v1/payment-methods/${momoId}/logo`)
        .set(auth(cashier))
        .attach("file", PNG, { filename: "logo.png", contentType: "image/png" })
        .expect(403);
      await request(server)
        .put(`/api/v1/payment-methods/${momoId}/logo`)
        .set(auth(a.token))
        .expect(400); // no file

      expect(
        (
          await request(server)
            .get(`/api/v1/payment-methods/${momoId}`)
            .set(auth(a.token))
            .expect(200)
        ).body.hasLogo,
      ).toBe(false);
    });

    it("removes the logo", async () => {
      const res = await request(server)
        .delete(`/api/v1/payment-methods/${orangeId}/logo`)
        .set(auth(a.token))
        .expect(200);
      expect(res.body.hasLogo).toBe(false);
      await request(server)
        .get(`/api/v1/payment-methods/${orangeId}/logo`)
        .set(auth(a.token))
        .expect(404);
    });
  });

  // ==========================================================================================
  describe("the customer chooses a payment method", () => {
    it("shows where to pay and the exact amount — computed by the server — and sells nothing", async () => {
      const stockBefore = await stockOf(a.token, waterId);
      const salesBefore = await salesCount(a.businessId);

      const p = await newPayment(2); // 2 × 5 000
      const res = await read(a.token, p.id).expect(200);

      expect(res.body).toMatchObject({
        status: "pending",
        amount: 10000,
        currency: "GNF",
        saleId: null,
        sale: null,
      });
      expect(res.body.method).toMatchObject({
        provider: "orange_money",
        displayName: "Orange Money",
        accountName: "Aissatou Diallo",
        phoneNumber: "622 12 34 56",
      });
      expect(res.body.method.instructionSteps).toHaveLength(8);
      expect(res.body.declaration).toBeNull();
      expect(await stockOf(a.token, waterId)).toBe(stockBefore);
      expect(await salesCount(a.businessId)).toBe(salesBefore);
    });

    it("takes a discount into account, and for a merchant code shows the code", async () => {
      const res = await start(a.token, {
        items: [{ productId: waterId, quantity: 2 }],
        discountTotal: 2000,
        paymentMethodId: codeId,
        clientRequestId: requestId(),
      }).expect(201);
      expect(res.body.amount).toBe(8000);
      expect(res.body.method).toMatchObject({
        provider: "merchant_code",
        merchantCode: "MARCHAND-77",
        phoneNumber: null,
      });
    });

    it('builds the "Payer maintenant" code from the owner’s template, and only when it is complete', async () => {
      await request(server)
        .patch(`/api/v1/payment-methods/${momoId}`)
        .set(auth(a.token))
        .send({ ussdCode: "*144*1*{numero}*{montant}#" })
        .expect(200);
      const p = await newPayment(2, momoId);
      expect((await read(a.token, p.id).expect(200)).body.method.ussdDial).toBe(
        "*144*1*666000001*10000#",
      );

      // {code} has nothing to fill it here: never offer a half-built code.
      await request(server)
        .patch(`/api/v1/payment-methods/${momoId}`)
        .set(auth(a.token))
        .send({ ussdCode: "*144*{code}#" })
        .expect(200);
      expect((await read(a.token, p.id).expect(200)).body.method.ussdDial).toBeNull();

      await request(server)
        .patch(`/api/v1/payment-methods/${momoId}`)
        .set(auth(a.token))
        .send({ ussdCode: "" })
        .expect(200);
    });

    it("never accepts an amount or a payment list from the client", async () => {
      const base = {
        items: [{ productId: waterId, quantity: 1 }],
        paymentMethodId: orangeId,
        clientRequestId: requestId(),
      };
      await start(a.token, { ...base, amount: 1 }).expect(400);
      await start(a.token, { ...base, payments: [{ method: "cash", amount: 5000 }] }).expect(400);
      await start(a.token, { ...base, status: "verified" }).expect(400);
    });

    it("is idempotent: the same key returns the same payment (double tap, refresh)", async () => {
      const key = requestId();
      const body = {
        items: [{ productId: waterId, quantity: 1 }],
        paymentMethodId: orangeId,
        clientRequestId: key,
      };
      const [first, second] = await Promise.all([start(a.token, body), start(a.token, body)]);
      const third = await start(a.token, body);

      expect([first.status, second.status, third.status]).toEqual([201, 201, 201]);
      expect(new Set([first.body.id, second.body.id, third.body.id]).size).toBe(1);
      const stored = await h.sql.query(
        "SELECT count(*) FROM biz.manual_payments WHERE business_id = $1 AND client_request_id = $2",
        [a.businessId, key],
      );
      expect(Number(stored.rows[0].count)).toBe(1);
    });

    it("refuses an inactive method, an unknown one, another business’s, and bad baskets", async () => {
      const inactive = await createMethod(a.token, {
        provider: "other",
        displayName: "Ancien",
        phoneNumber: "620000001",
        isActive: false,
      }).expect(201);
      const base = { items: [{ productId: waterId, quantity: 1 }], clientRequestId: requestId() };

      await start(a.token, { ...base, paymentMethodId: inactive.body.id }).expect(400);
      await start(a.token, {
        ...base,
        clientRequestId: requestId(),
        paymentMethodId: "11111111-1111-4111-8111-111111111111",
      }).expect(404);
      await start(b.token, {
        ...base,
        clientRequestId: requestId(),
        paymentMethodId: orangeId,
      }).expect(404); // A's method
      await start(b.token, {
        ...base,
        clientRequestId: requestId(),
        paymentMethodId: (
          await createMethod(b.token, {
            provider: "orange_money",
            phoneNumber: "620000002",
          }).expect(201)
        ).body.id,
      }).expect(404); // A's product

      const okMethod = { paymentMethodId: orangeId };
      await start(a.token, {
        ...okMethod,
        items: [{ productId: oddId, quantity: 1.5 }],
        clientRequestId: requestId(),
      }).expect(400); // 3 001.5
      await start(a.token, {
        ...okMethod,
        items: [{ productId: waterId, quantity: 1 }],
        discountTotal: 999999,
        clientRequestId: requestId(),
      }).expect(400);
      await start(a.token, { ...okMethod, items: [{ productId: waterId, quantity: 1 }] }).expect(
        400,
      ); // no key
      await start(a.token, { ...okMethod, items: [], clientRequestId: requestId() }).expect(400);
      await start(a.token, {
        ...okMethod,
        items: [{ productId: "11111111-1111-4111-8111-111111111111", quantity: 1 }],
        clientRequestId: requestId(),
      }).expect(404);
      await request(server)
        .post("/api/v1/payments")
        .send({ ...base, paymentMethodId: orangeId })
        .expect(401);
    });

    it("freezes what the customer was told: editing the method later does not change this payment", async () => {
      const p = await newPayment(2, momoId);
      await request(server)
        .patch(`/api/v1/payment-methods/${momoId}`)
        .set(auth(a.token))
        .send({ phoneNumber: "666 99 99 99", accountName: "Autre Personne" })
        .expect(200);

      const res = await read(a.token, p.id).expect(200);
      expect(res.body.method).toMatchObject({
        phoneNumber: "666 00 00 01",
        accountName: "Aissatou Diallo",
      });

      await request(server)
        .patch(`/api/v1/payment-methods/${momoId}`)
        .set(auth(a.token))
        .send({ phoneNumber: "666 00 00 01", accountName: "Aissatou Diallo" })
        .expect(200);
    });

    it("keeps a used method (deactivate instead of delete), and removes an unused one", async () => {
      await request(server)
        .delete(`/api/v1/payment-methods/${orangeId}`)
        .set(auth(a.token))
        .expect(409);
      const fresh = await createMethod(a.token, {
        provider: "other",
        phoneNumber: "620000003",
      }).expect(201);
      await request(server)
        .delete(`/api/v1/payment-methods/${fresh.body.id}`)
        .set(auth(a.token))
        .expect(204);
    });
  });

  // ==========================================================================================
  describe('"J’ai effectué le paiement": the declaration', () => {
    it("records the declaration and waits for the owner — it is NOT paid, nothing is sold", async () => {
      const salesBefore = await salesCount(a.businessId);
      const stockBefore = await stockOf(a.token, waterId);
      const p = await newPayment(2);

      const res = await submit(
        a.token,
        p.id,
        declaration(10000, { transactionReference: "MP240921.1234.A56789" }),
      ).expect(201);

      expect(res.body.status).toBe("submitted");
      expect(res.body.declaration).toMatchObject({
        payerName: "Mamadou Bah",
        payerPhone: "655 11 22 33",
        transactionReference: "MP240921.1234.A56789",
        amountSent: 10000,
      });
      expect(res.body.declaration.submittedAt).toBeTruthy();
      expect(res.body.saleId).toBeNull();
      expect(res.body.verifiedAt).toBeNull();
      expect(await salesCount(a.businessId)).toBe(salesBefore);
      expect(await stockOf(a.token, waterId)).toBe(stockBefore);
    });

    it("refuses an empty, too short or malformed reference", async () => {
      const p = await newPayment(2);
      for (const transactionReference of [
        "",
        "   ",
        "ab",
        "x!x!x!",
        "<script>alert(1)</script>",
        "a".repeat(65),
      ]) {
        await submit(a.token, p.id, declaration(10000, { transactionReference })).expect(400);
      }
      await submit(a.token, p.id, { payerPhone: "655112233", amountSent: 10000 }).expect(400); // missing
      expect((await read(a.token, p.id).expect(200)).body.status).toBe("pending");
    });

    it("refuses a wrong amount — the exact amount is required", async () => {
      const p = await newPayment(2);
      for (const amountSent of [9999, 10001, 5000, 0, -10000]) {
        const res = await submit(a.token, p.id, declaration(amountSent)).expect(400);
        if (amountSent === 5000) expect(res.body.error.message).toContain("exactement");
      }
      await submit(a.token, p.id, declaration(10000, { amountSent: "10000" })).expect(400); // text is not a number
    });

    it("refuses a bad payer number and impossible dates", async () => {
      const p = await newPayment(2);
      for (const payerPhone of ["", "abc", "12", "6".repeat(20)]) {
        await submit(a.token, p.id, declaration(10000, { payerPhone })).expect(400);
      }
      const future = new Date(Date.now() + 3 * 60 * 60 * 1000).toISOString();
      const old = new Date(Date.now() - 45 * 24 * 60 * 60 * 1000).toISOString();
      await submit(a.token, p.id, declaration(10000, { paidAt: future })).expect(400);
      await submit(a.token, p.id, declaration(10000, { paidAt: old })).expect(400);
      await submit(a.token, p.id, declaration(10000, { paidAt: "pas une date" })).expect(400);

      const recent = new Date(Date.now() - 60 * 60 * 1000).toISOString();
      const ok = await submit(a.token, p.id, declaration(10000, { paidAt: recent })).expect(201);
      expect(new Date(ok.body.declaration.paidAt).toISOString()).toBe(recent);
    });

    it("survives a double click and a page refresh: the same declaration changes nothing", async () => {
      const p = await newPayment(2);
      const body = declaration(10000, { transactionReference: tx() });

      const results = await Promise.all([
        submit(a.token, p.id, body),
        submit(a.token, p.id, body),
        submit(a.token, p.id, body),
      ]);
      expect(results.map((r) => r.status).sort()).toEqual([201, 201, 201]);
      const again = await submit(a.token, p.id, body).expect(201);
      expect(again.body.status).toBe("submitted");

      // …but a DIFFERENT declaration on an already declared payment is refused.
      await submit(a.token, p.id, { ...body, transactionReference: tx() }).expect(409);
    });

    it("does not let one transaction reference pay two orders — however it is written", async () => {
      const ref = "OM-2024.09-A1B2C3";
      await submittedPayment(2, orangeId, ref);

      for (const variant of [ref, ref.toLowerCase(), "om 2024 09 a1b2c3", "OM2024.09A1B2C3"]) {
        const other = await newPayment(2);
        const res = await submit(
          a.token,
          other.id,
          declaration(10000, { transactionReference: variant }),
        ).expect(409);
        expect(res.body.error.message).toContain("déjà été utilisée");
      }
    });

    it("scopes a reference to its operator and business, and frees it once rejected or cancelled", async () => {
      const ref = tx();
      const first = await submittedPayment(2, orangeId, ref);

      // the same text on another operator, or in another business, is a different transaction
      const onMomo = await newPayment(2, momoId);
      await submit(a.token, onMomo.id, declaration(10000, { transactionReference: ref })).expect(
        201,
      );
      const bMethod = (
        await createMethod(b.token, { provider: "orange_money", phoneNumber: "620000009" }).expect(
          201,
        )
      ).body.id;
      const bProduct = await product(b.token, "Eau B", 5000, 10);
      const bPay = (
        await start(b.token, {
          items: [{ productId: bProduct, quantity: 2 }],
          paymentMethodId: bMethod,
          clientRequestId: requestId(),
        }).expect(201)
      ).body;
      await submit(b.token, bPay.id, declaration(10000, { transactionReference: ref })).expect(201);

      // rejected → the reference is free again (the customer may have mistyped it)
      await reject(a.token, first.id, { reason: "Transaction introuvable" }).expect(201);
      const retry = await newPayment(2);
      await submit(a.token, retry.id, declaration(10000, { transactionReference: ref })).expect(
        201,
      );

      // cancelled → free again
      await cancel(a.token, retry.id).expect(201);
      const again = await newPayment(2);
      await submit(a.token, again.id, declaration(10000, { transactionReference: ref })).expect(
        201,
      );
    });

    it("lets the database, not just the code, guard the reference against simultaneous declarations", async () => {
      const ref = tx();
      const [p1, p2, p3] = await Promise.all([newPayment(2), newPayment(2), newPayment(2)]);
      const results = await Promise.all(
        [p1, p2, p3].map((p) =>
          submit(a.token, p.id, declaration(10000, { transactionReference: ref })),
        ),
      );
      expect(results.map((r) => r.status).sort()).toEqual([201, 409, 409]);
    });

    it("lets a rejected payment be declared again with corrected details", async () => {
      const p = await submittedPayment(2, orangeId, tx());
      await reject(a.token, p.id, { reason: "Référence invalide" }).expect(201);
      expect((await read(a.token, p.id).expect(200)).body.rejectionReason).toBe(
        "Référence invalide",
      );

      const fixed = await submit(
        a.token,
        p.id,
        declaration(10000, { transactionReference: tx() }),
      ).expect(201);
      expect(fixed.body.status).toBe("submitted");
      expect(fixed.body.rejectionReason).toBeNull();
    });

    it("refuses to declare a payment that is cancelled or already verified", async () => {
      const c = await newPayment(2);
      await cancel(a.token, c.id).expect(201);
      await submit(a.token, c.id, declaration(10000)).expect(409);

      const v = await submittedPayment(2);
      await verify(a.token, v.id).expect(201);
      await submit(a.token, v.id, declaration(10000)).expect(409);
    });

    it("needs a login, and hides another business’s payment (404)", async () => {
      const p = await newPayment(2);
      await request(server)
        .post(`/api/v1/payments/${p.id}/submit`)
        .send(declaration(10000))
        .expect(401);
      await submit(b.token, p.id, declaration(10000)).expect(404);
      await submit(a.token, "11111111-1111-4111-8111-111111111111", declaration(10000)).expect(404);
      await submit(a.token, "not-a-uuid", declaration(10000)).expect(400);
    });
  });

  // ==========================================================================================
  describe("proof of payment", () => {
    it("attaches a picture to a declared payment and serves it back to the business only", async () => {
      const p = await submittedPayment();
      const res = await request(server)
        .put(`/api/v1/payments/${p.id}/proof`)
        .set(auth(a.token))
        .attach("file", PNG, { filename: "capture.png", contentType: "image/png" })
        .expect(200);
      expect(res.body.hasProof).toBe(true);
      expect(res.body.status).toBe("submitted"); // a picture proves nothing by itself

      const proof = await request(server)
        .get(`/api/v1/payments/${p.id}/proof`)
        .set(auth(a.token))
        .expect(200);
      expect(proof.headers["content-type"]).toBe("image/png");
      expect(proof.headers["cache-control"]).toContain("no-store");
      expect(Buffer.compare(proof.body, PNG)).toBe(0);

      await request(server).get(`/api/v1/payments/${p.id}/proof`).set(auth(b.token)).expect(404);
      await request(server).get(`/api/v1/payments/${p.id}/proof`).expect(401);
    });

    it("refuses fake, oversized and missing files", async () => {
      const p = await submittedPayment();
      await request(server)
        .put(`/api/v1/payments/${p.id}/proof`)
        .set(auth(a.token))
        .attach("file", Buffer.from('<?php system($_GET["c"]); ?>'), {
          filename: "preuve.jpg",
          contentType: "image/jpeg",
        })
        .expect(400);
      await request(server)
        .put(`/api/v1/payments/${p.id}/proof`)
        .set(auth(a.token))
        .attach("file", bigPng(3 * 1024 * 1024 + 10), {
          filename: "big.png",
          contentType: "image/png",
        })
        .expect(413);
      await request(server).put(`/api/v1/payments/${p.id}/proof`).set(auth(a.token)).expect(400);
      expect((await read(a.token, p.id).expect(200)).body.hasProof).toBe(false);
    });

    it("cannot be changed once the payment is decided, and can be removed before", async () => {
      const p = await submittedPayment();
      await request(server)
        .put(`/api/v1/payments/${p.id}/proof`)
        .set(auth(a.token))
        .attach("file", PNG, { filename: "a.png" })
        .expect(200);
      const removed = await request(server)
        .delete(`/api/v1/payments/${p.id}/proof`)
        .set(auth(a.token))
        .expect(200);
      expect(removed.body.hasProof).toBe(false);
      await request(server).get(`/api/v1/payments/${p.id}/proof`).set(auth(a.token)).expect(404);

      await verify(a.token, p.id).expect(201);
      await request(server)
        .put(`/api/v1/payments/${p.id}/proof`)
        .set(auth(a.token))
        .attach("file", PNG, { filename: "a.png" })
        .expect(409);
    });
  });

  // ==========================================================================================
  describe("the owner verifies", () => {
    it("records the sale once the owner validates: paid, stock down, reference kept", async () => {
      const salesBefore = await salesCount(a.businessId);
      const stockBefore = await stockOf(a.token, waterId);
      const ref = tx();
      const p = await submittedPayment(2, orangeId, ref);

      const res = await verify(a.token, p.id).expect(201);

      expect(res.body.status).toBe("verified");
      expect(res.body.verifiedAt).toBeTruthy();
      expect(res.body.needsAttention).toBe(false);
      expect(res.body.saleId).toBeTruthy();
      expect(await salesCount(a.businessId)).toBe(salesBefore + 1);
      expect(await stockOf(a.token, waterId)).toBe(stockBefore - 2);

      const sale = res.body.sale;
      expect(Number(sale.total)).toBe(10000);
      expect(Number(sale.amountPaid)).toBe(10000);
      expect(Number(sale.amountDue)).toBe(0);
      expect(sale.status).toBe("completed");
      expect(sale.soldBy).toBe(a.userId);
      expect(sale.payments).toHaveLength(1);
      expect(sale.payments[0]).toMatchObject({ method: "mobile_money", providerReference: ref });

      const row = await h.sql.query("SELECT verified_by FROM biz.manual_payments WHERE id = $1", [
        p.id,
      ]);
      expect(row.rows[0].verified_by).toBe(a.userId);
    });

    it("is reserved to the owner: a cashier can declare, not verify", async () => {
      const p = await submittedPayment();
      await verify(cashier, p.id).expect(403);
      await reject(cashier, p.id, { reason: "x" }).expect(403);
      expect((await read(a.token, p.id).expect(200)).body.status).toBe("submitted");
      await verify(a.token, p.id).expect(201);

      // …but the cashier can start and declare payments.
      const started = await start(cashier, {
        items: [{ productId: waterId, quantity: 1 }],
        paymentMethodId: orangeId,
        clientRequestId: requestId(),
      }).expect(201);
      await submit(cashier, started.body.id, declaration(5000)).expect(201);
    });

    it("verifying twice — or many times at once — records one sale", async () => {
      const salesBefore = await salesCount(a.businessId);
      const p = await submittedPayment();

      const results = await Promise.all([
        verify(a.token, p.id),
        verify(a.token, p.id),
        verify(a.token, p.id),
      ]);
      const again = await verify(a.token, p.id).expect(201);

      expect(results.map((r) => r.status)).toEqual([201, 201, 201]);
      expect(new Set([...results.map((r) => r.body.saleId), again.body.saleId]).size).toBe(1);
      expect(await salesCount(a.businessId)).toBe(salesBefore + 1);
    });

    it("records the sale at the prices the customer was shown, even if a price changes meanwhile", async () => {
      const p = await submittedPayment(2); // 10 000
      await request(server)
        .patch(`/api/v1/products/${waterId}`)
        .set(auth(a.token))
        .send({ salePrice: 6000 })
        .expect(200);

      const res = await verify(a.token, p.id).expect(201);
      expect(Number(res.body.sale.total)).toBe(10000);
      expect(Number(res.body.sale.items[0].unitPrice)).toBe(5000);

      await request(server)
        .patch(`/api/v1/products/${waterId}`)
        .set(auth(a.token))
        .send({ salePrice: 5000 })
        .expect(200);
    });

    it("still records the sale when the stock ran out meanwhile (the money is in)", async () => {
      const p = (
        await start(a.token, {
          items: [{ productId: riceId, quantity: 3 }],
          paymentMethodId: orangeId,
          clientRequestId: requestId(),
        }).expect(201)
      ).body;
      await submit(a.token, p.id, declaration(p.amount)).expect(201);
      await request(server)
        .post("/api/v1/sales")
        .set(auth(a.token))
        .send({
          items: [{ productId: riceId, quantity: 4 }],
          payments: [{ method: "cash", amount: 4 * 220000 }],
        })
        .expect(201);

      const res = await verify(a.token, p.id).expect(201);
      expect(res.body.saleId).toBeTruthy();
      expect(await stockOf(a.token, riceId)).toBe(-2);
    });

    it("attaches the customer to the sale when there is one", async () => {
      const customer = await request(server)
        .post("/api/v1/customers")
        .set(auth(a.token))
        .send({ fullName: "Fatou Camara" })
        .expect(201);
      const p = (
        await start(a.token, {
          items: [{ productId: waterId, quantity: 1 }],
          paymentMethodId: orangeId,
          customerId: customer.body.id,
          clientRequestId: requestId(),
        }).expect(201)
      ).body;
      await submit(a.token, p.id, declaration(5000)).expect(201);

      const res = await verify(a.token, p.id).expect(201);
      expect(res.body.sale.customer.id).toBe(customer.body.id);
    });

    it("refuses to verify what was not declared, or was decided otherwise", async () => {
      const pending = await newPayment(2);
      await verify(a.token, pending.id).expect(409);

      const rejected = await submittedPayment();
      await reject(a.token, rejected.id).expect(201);
      await verify(a.token, rejected.id).expect(409);

      const cancelled = await submittedPayment();
      await cancel(a.token, cancelled.id).expect(201);
      await verify(a.token, cancelled.id).expect(409);
    });

    it("never loses a verified payment when the sale cannot be recorded: verify again to finish", async () => {
      const customer = await request(server)
        .post("/api/v1/customers")
        .set(auth(a.token))
        .send({ fullName: "Client éphémère" })
        .expect(201);
      const p = (
        await start(a.token, {
          items: [{ productId: waterId, quantity: 1 }],
          paymentMethodId: orangeId,
          customerId: customer.body.id,
          clientRequestId: requestId(),
        }).expect(201)
      ).body;
      await submit(a.token, p.id, declaration(5000)).expect(201);
      await h.sql.query("DELETE FROM biz.customers WHERE id = $1", [customer.body.id]); // the sale can no longer be recorded

      const stuck = await verify(a.token, p.id).expect(201);
      expect(stuck.body.status).toBe("verified"); // the owner's decision stands
      expect(stuck.body.saleId).toBeNull();
      expect(stuck.body.needsAttention).toBe(true);

      await h.sql.query(
        "INSERT INTO biz.customers (id, business_id, full_name) VALUES ($1, $2, 'Client éphémère')",
        [customer.body.id, a.businessId],
      );
      const done = await verify(a.token, p.id).expect(201);
      expect(done.body.saleId).toBeTruthy();
      expect(done.body.needsAttention).toBe(false);
      const recorded = await h.sql.query(
        `SELECT count(*) FROM biz.sales
          WHERE client_request_id = (SELECT client_request_id FROM biz.manual_payments WHERE id = $1)`,
        [p.id],
      );
      expect(Number(recorded.rows[0].count)).toBe(1);
    });

    it("hides another business’s payment from the verification (404)", async () => {
      const p = await submittedPayment();
      await verify(b.token, p.id).expect(404);
      await reject(b.token, p.id).expect(404);
      expect((await read(a.token, p.id).expect(200)).body.status).toBe("submitted");
      await request(server).post(`/api/v1/payments/${p.id}/verify`).expect(401);
    });
  });

  // ==========================================================================================
  describe("the owner refuses", () => {
    it("records the reason, shows it, and sells nothing", async () => {
      const salesBefore = await salesCount(a.businessId);
      const p = await submittedPayment();

      const res = await reject(a.token, p.id, { reason: "  Montant   incorrect " }).expect(201);
      expect(res.body.status).toBe("rejected");
      expect(res.body.rejectionReason).toBe("Montant incorrect");
      expect(res.body.rejectedAt).toBeTruthy();
      expect(res.body.saleId).toBeNull();
      expect(await salesCount(a.businessId)).toBe(salesBefore);

      const row = await h.sql.query("SELECT rejected_by FROM biz.manual_payments WHERE id = $1", [
        p.id,
      ]);
      expect(row.rows[0].rejected_by).toBe(a.userId);
    });

    it("accepts no reason, refuses an oversized one, and is idempotent", async () => {
      const p = await submittedPayment();
      await reject(a.token, p.id, { reason: "x".repeat(201) }).expect(400);
      const res = await reject(a.token, p.id).expect(201);
      expect(res.body.rejectionReason).toBeNull();
      await reject(a.token, p.id, { reason: "autre motif" }).expect(201); // already rejected: unchanged
      expect((await read(a.token, p.id).expect(200)).body.rejectionReason).toBeNull();
    });

    it("cannot refuse a payment that was not declared or is already validated", async () => {
      const pending = await newPayment(2);
      await reject(a.token, pending.id).expect(409);
      const verified = await submittedPayment();
      await verify(a.token, verified.id).expect(201);
      await reject(a.token, verified.id).expect(409);
    });
  });

  // ==========================================================================================
  describe("cancelling, and unpaid orders", () => {
    it("lets the team cancel a payment nobody made, and only the owner one already declared", async () => {
      const pending = await newPayment(2);
      const res = await cancel(cashier, pending.id).expect(201);
      expect(res.body.status).toBe("cancelled");
      expect(res.body.cancelledAt).toBeTruthy();
      await cancel(cashier, pending.id).expect(201); // idempotent

      const declared = await submittedPayment();
      await cancel(cashier, declared.id).expect(403);
      await cancel(a.token, declared.id).expect(201);
    });

    it("cannot cancel a validated payment (cancel the sale instead)", async () => {
      const p = await submittedPayment();
      await verify(a.token, p.id).expect(201);
      const res = await cancel(a.token, p.id).expect(409);
      expect(res.body.error.message).toContain("annulez la vente");
    });

    it("keeps an unpaid payment as it is: nothing is deleted or sold automatically", async () => {
      const p = await newPayment(2);
      await h.sql.query("UPDATE biz.manual_payments SET created_at = $2 WHERE id = $1", [
        p.id,
        new Date(Date.now() - 10 * 24 * 60 * 60 * 1000),
      ]);

      const res = await read(a.token, p.id).expect(200);
      expect(res.body.status).toBe("pending");
      expect(res.body.saleId).toBeNull();
    });
  });

  // ==========================================================================================
  describe("lists, summary and isolation", () => {
    it("lists the business’s payments, newest first, filtered by status and paginated", async () => {
      const all = await request(server).get("/api/v1/payments").set(auth(a.token)).expect(200);
      expect(all.body.total).toBeGreaterThan(10);
      const dates = all.body.items.map((i: any) => new Date(i.createdAt).getTime());
      expect([...dates].sort((x, y) => y - x)).toEqual(dates);

      const submitted = await request(server)
        .get("/api/v1/payments?status=submitted&pageSize=100")
        .set(auth(a.token))
        .expect(200);
      expect(submitted.body.items.length).toBeGreaterThan(0);
      expect(submitted.body.items.every((i: any) => i.status === "submitted")).toBe(true);
      expect(submitted.body.items[0].method.displayName).toBeTruthy();

      const page = await request(server)
        .get("/api/v1/payments?pageSize=2&page=2")
        .set(auth(a.token))
        .expect(200);
      expect(page.body.items).toHaveLength(2);
      expect(page.body.page).toBe(2);

      await request(server).get("/api/v1/payments?status=paid").set(auth(a.token)).expect(400);
      await request(server).get("/api/v1/payments?pageSize=0").set(auth(a.token)).expect(400);
    });

    it('counts payments per status (the "à vérifier" badge)', async () => {
      const summary = await request(server)
        .get("/api/v1/payments/summary")
        .set(auth(a.token))
        .expect(200);
      expect(Object.keys(summary.body).sort()).toEqual([
        "cancelled",
        "pending",
        "rejected",
        "submitted",
        "verified",
      ]);
      for (const status of Object.keys(summary.body)) {
        const real = await h.sql.query(
          "SELECT count(*) FROM biz.manual_payments WHERE business_id = $1 AND status = $2",
          [a.businessId, status],
        );
        expect(summary.body[status]).toBe(Number(real.rows[0].count));
      }
    });

    it("shows nothing of another business — lists, counts, details, decisions", async () => {
      const list = await request(server).get("/api/v1/payments").set(auth(b.token)).expect(200);
      const ids = list.body.items.map((i: any) => i.id);
      const aPayment = (
        await h.sql.query("SELECT id FROM biz.manual_payments WHERE business_id = $1 LIMIT 1", [
          a.businessId,
        ])
      ).rows[0] as { id: string };
      expect(ids).not.toContain(aPayment.id);

      const summary = await request(server)
        .get("/api/v1/payments/summary")
        .set(auth(b.token))
        .expect(200);
      expect(summary.body.submitted).toBeLessThanOrEqual(1);
      await read(b.token, aPayment.id).expect(404);
      await cancel(b.token, aPayment.id).expect(404);
    });

    it("needs a login everywhere", async () => {
      await request(server).get("/api/v1/payments").expect(401);
      await request(server).get("/api/v1/payments/summary").expect(401);
      await request(server)
        .get(
          `/api/v1/payments/${(await h.sql.query("SELECT id FROM biz.manual_payments LIMIT 1")).rows[0].id}`,
        )
        .expect(401);
    });
  });
});
