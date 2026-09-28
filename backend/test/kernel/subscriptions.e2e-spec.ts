import request from "supertest";
import { rolloutBucket } from "../../src/modules/subscriptions/feature-flags.service.js";
import {
  API,
  createBusiness,
  createHarness,
  loginWithOtp,
  uniquePhone,
  type Harness,
} from "../harness.js";

const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });

describe("Abonnements, droits et feature flags (e2e)", () => {
  let h: Harness;
  const get = (token: string, path: string) =>
    request(h.server).get(`${API}${path}`).set(bearer(token));
  const post = (token: string, path: string, body: object = {}) =>
    request(h.server).post(`${API}${path}`).set(bearer(token)).send(body);

  beforeAll(async () => {
    h = await createHarness();
  });
  afterAll(async () => {
    await h.close();
  });

  async function freeBusiness() {
    const s = await loginWithOtp(h, uniquePhone());
    const b = await createBusiness(h, s, "Offre gratuite", { freePlan: true });
    return { session: s, ...b };
  }

  it("une nouvelle entreprise est sur l'offre gratuite, avec ses droits et son occupation", async () => {
    const b = await freeBusiness();
    const res = await get(b.accessToken, `/businesses/${b.businessId}/subscription`).expect(200);
    expect(res.body).toMatchObject({
      plan: { code: "FREE", name: "Gratuit" },
      status: "ACTIVE",
      entitlements: { "members.max": 3, "products.max": 50, "reports.export": 0 },
      usage: { "members.max": 1, "products.max": 0 },
    });
    const events = await h.sql.query(
      "SELECT type, to_plan FROM sub.subscription_events WHERE business_id = $1",
      [b.businessId],
    );
    expect(events.rows).toEqual([{ type: "STARTED", to_plan: "FREE" }]);
  });

  it("tout membre voit l'offre ; une autre entreprise reçoit 404", async () => {
    const b = await freeBusiness();
    const other = await freeBusiness();
    await get(other.accessToken, `/businesses/${b.businessId}/subscription`).expect(404);
  });

  it("la limite de membres compte les invitations en attente, et bloque la suivante", async () => {
    const b = await freeBusiness();
    const invite = (phone = uniquePhone()) =>
      post(b.accessToken, `/businesses/${b.businessId}/invitations`, {
        phone,
        roleCode: "CASHIER",
      });
    const first = uniquePhone();
    await invite(first).expect(201);
    await invite().expect(201); // 1 propriétaire + 2 invitations = 3 places
    const blocked = await invite();
    expect(blocked.status).toBe(403);
    expect(blocked.body.error).toMatchObject({
      code: "ENTITLEMENT_LIMIT_REACHED",
      details: { entitlement: "members.max", limit: 3 },
    });
    // Réinviter un numéro déjà invité ne prend pas de place supplémentaire.
    await invite(first).expect(201);
  });

  it("la limite de produits actifs bloque le suivant ; désactiver libère une place", async () => {
    const b = await freeBusiness();
    await h.sql.query(
      `INSERT INTO sub.entitlement_overrides (business_id, entitlement_code, value, reason)
       VALUES ($1, 'products.max', 2, 'test')`,
      [b.businessId],
    );
    const create = (name: string) => post(b.accessToken, "/products", { name, salePrice: 1000 });
    const p1 = (await create("A").expect(201)).body;
    await create("B").expect(201);
    const blocked = await create("C");
    expect(blocked.status).toBe(403);
    expect(blocked.body.error.code).toBe("ENTITLEMENT_LIMIT_REACHED");

    await request(h.server)
      .delete(`${API}/products/${p1.id}`)
      .set(bearer(b.accessToken))
      .expect((r) => {
        expect(r.status).toBeLessThan(300);
      });
    await create("C").expect(201);
    // Réactiver A dépasserait la limite.
    const reactivate = await request(h.server)
      .patch(`${API}/products/${p1.id}`)
      .set(bearer(b.accessToken))
      .send({ isActive: true });
    expect(reactivate.status).toBe(403);
  });

  it("une dérogation expirée ne compte plus ; un abonnement expiré retombe sur le gratuit", async () => {
    const b = await freeBusiness();
    await h.sql.query(
      `INSERT INTO sub.entitlement_overrides (business_id, entitlement_code, value, reason, expires_at)
       VALUES ($1, 'members.max', 10, 'promo', now() - interval '1 day')`,
      [b.businessId],
    );
    await h.sql.query(
      "UPDATE sub.subscriptions SET plan_code = 'PRO', status = 'EXPIRED' WHERE business_id = $1",
      [b.businessId],
    );
    const res = await get(b.accessToken, `/businesses/${b.businessId}/subscription`).expect(200);
    expect(res.body.plan.code).toBe("PRO");
    expect(res.body.status).toBe("EXPIRED");
    expect(res.body.entitlements["members.max"]).toBe(3); // droits du gratuit, données conservées
  });

  describe("feature flags", () => {
    afterAll(async () => {
      await h.sql.query("DELETE FROM ops.feature_flags WHERE key LIKE 'test.%'");
    });

    it("kill-switch, pays et déploiement progressif", async () => {
      const s = await loginWithOtp(h, uniquePhone());
      const b = await createBusiness(h, s, "Flags");
      const bucket = rolloutBucket("test.rollout", s.userId);
      await h.sql.query(
        `INSERT INTO ops.feature_flags (key, description, enabled, rollout_percent, countries) VALUES
           ('test.on', 'actif', true, 100, NULL),
           ('test.off', 'coupé', false, 100, NULL),
           ('test.gn', 'Guinée seulement', true, 100, ARRAY['GN']),
           ('test.sn', 'Sénégal seulement', true, 100, ARRAY['SN']),
           ('test.rollout', 'progressif', true, $1, NULL)
         ON CONFLICT (key) DO NOTHING`,
        [bucket + 1], // juste assez pour inclure cet utilisateur
      );
      const res = await get(b.accessToken, "/me/feature-flags").expect(200);
      const flags = (res.body.flags as string[]).filter((f) => f.startsWith("test."));
      expect(flags.sort()).toEqual(["test.gn", "test.on", "test.rollout"]);

      await h.sql.query(
        "UPDATE ops.feature_flags SET rollout_percent = $1 WHERE key = 'test.rollout'",
        [bucket],
      );
      const after = await get(b.accessToken, "/me/feature-flags").expect(200);
      expect(after.body.flags).not.toContain("test.rollout");
    });
  });
});
