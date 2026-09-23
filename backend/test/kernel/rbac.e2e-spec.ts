import request from "supertest";
import {
  API,
  createBusiness,
  createHarness,
  loginWithOtp,
  uniquePhone,
  type Harness,
  type Session,
} from "../harness.js";

const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });

interface Member {
  phone: string;
  session: Session;
  token: string; // jeton avec l'entreprise A active
  role: string;
}

describe("RBAC — rôles, invitations, surcharges de permissions (e2e)", () => {
  let h: Harness;
  let owner: { session: Session; token: string; businessId: string };
  let other: { token: string; businessId: string };
  const members: Record<string, Member> = {};

  async function invite(role: string): Promise<Member> {
    const phone = uniquePhone();
    const invitation = await request(h.server)
      .post(`${API}/businesses/${owner.businessId}/invitations`)
      .set(bearer(owner.token))
      .send({ phone, roleCode: role })
      .expect(201);
    const session = await loginWithOtp(h, phone);
    await request(h.server)
      .post(`${API}/invitations/accept`)
      .set(bearer(session.accessToken))
      .send({ token: invitation.body.token })
      .expect(200);
    const activated = await request(h.server)
      .post(`${API}/businesses/${owner.businessId}/activate`)
      .set(bearer(session.accessToken))
      .expect(200);
    return { phone, session, token: activated.body.accessToken, role: activated.body.role };
  }

  beforeAll(async () => {
    h = await createHarness();
    const s = await loginWithOtp(h, uniquePhone());
    const b = await createBusiness(h, s, "RBAC A");
    owner = { session: s, token: b.accessToken, businessId: b.businessId };
    const s2 = await loginWithOtp(h, uniquePhone());
    const b2 = await createBusiness(h, s2, "RBAC B");
    other = { token: b2.accessToken, businessId: b2.businessId };

    for (const role of ["ADMIN", "MANAGER", "CASHIER", "STOCK_KEEPER", "ACCOUNTANT", "VIEWER"]) {
      members[role] = await invite(role);
    }
  });
  afterAll(async () => {
    await h.close();
  });

  const get = (token: string, path: string) =>
    request(h.server).get(`${API}${path}`).set(bearer(token));
  const post = (token: string, path: string, body: object = {}) =>
    request(h.server).post(`${API}${path}`).set(bearer(token)).send(body);

  describe("invitations", () => {
    it("chaque invité obtient son rôle et exactement les permissions de ce rôle", async () => {
      for (const [role, m] of Object.entries(members)) expect(m.role).toBe(role);

      const cashier = await post(
        members["CASHIER"]!.token,
        `/businesses/${owner.businessId}/activate`,
      );
      expect(cashier.body.permissions).toEqual(
        expect.arrayContaining(["sales:create", "catalog:view", "payments:declare"]),
      );
      expect(cashier.body.permissions).not.toContain("products:manage");
      expect(cashier.body.permissions).not.toContain("members:manage");
    });

    it("refuse d'accepter une invitation avec un autre numéro que celui invité", async () => {
      const inv = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone: uniquePhone(),
        roleCode: "VIEWER",
      }).expect(201);
      const stranger = await loginWithOtp(h, uniquePhone());
      const res = await post(stranger.accessToken, "/invitations/accept", {
        token: inv.body.token,
      });
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe("INVITATION_PHONE_MISMATCH");
    });

    it("une invitation ne sert qu'une fois", async () => {
      const phone = uniquePhone();
      const inv = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone,
        roleCode: "VIEWER",
      }).expect(201);
      const session = await loginWithOtp(h, phone);
      await post(session.accessToken, "/invitations/accept", { token: inv.body.token }).expect(200);
      const again = await post(session.accessToken, "/invitations/accept", {
        token: inv.body.token,
      });
      expect(again.status).toBe(422);
      expect(again.body.error.code).toBe("INVITATION_INVALID");
    });

    it("ne permet pas d'inviter un OWNER (le transfert de propriété est un flux à part)", async () => {
      await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone: uniquePhone(),
        roleCode: "OWNER",
      }).expect(400);
    });

    it("le jeton d'invitation n'est stocké que haché", async () => {
      const inv = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone: uniquePhone(),
        roleCode: "VIEWER",
      }).expect(201);
      const row = await h.sql.query(
        "SELECT count(*)::int AS n FROM core.business_invitations WHERE token_hash = convert_to($1, 'UTF8')",
        [inv.body.token],
      );
      expect(row.rows[0].n).toBe(0);
    });
  });

  describe("matrice rôle × action", () => {
    const productBody = () => ({ name: `Produit ${Math.random()}`, salePrice: 1000 });
    const canManageProducts = ["ADMIN", "MANAGER", "STOCK_KEEPER"];
    const canSeeDashboard = ["ADMIN", "MANAGER", "ACCOUNTANT", "VIEWER"];

    it("tous les rôles voient le catalogue", async () => {
      for (const m of Object.values(members)) await get(m.token, "/products").expect(200);
    });

    it("seuls les rôles avec products:manage créent un produit", async () => {
      for (const [role, m] of Object.entries(members)) {
        const res = await post(m.token, "/products", productBody());
        expect(res.status, role).toBe(canManageProducts.includes(role) ? 201 : 403);
      }
    });

    it("seuls les rôles avec reports:view voient le tableau de bord", async () => {
      for (const [role, m] of Object.entries(members)) {
        const res = await get(m.token, "/dashboard/summary?period=today");
        expect(res.status, role).toBe(canSeeDashboard.includes(role) ? 200 : 403);
      }
    });

    it("le bénéfice n'est montré qu'avec finance:view_profit", async () => {
      const withProfit = ["ADMIN", "ACCOUNTANT"];
      for (const role of canSeeDashboard) {
        const res = await get(members[role]!.token, "/dashboard/summary?period=today").expect(200);
        if (withProfit.includes(role)) expect(res.body.profit, role).not.toBeNull();
        else {
          expect(res.body.profit, role).toBeNull();
          expect(res.body.cogs, role).toBeNull();
        }
      }
      const asOwner = await get(owner.token, "/dashboard/summary?period=today").expect(200);
      expect(asOwner.body.profit).not.toBeNull();
    });

    it("la caisse (sales:create) est ouverte au caissier, fermée au lecteur et au magasinier", async () => {
      const product = (
        await post(owner.token, "/products", { ...productBody(), initialStock: 10 }).expect(201)
      ).body;
      const sale = {
        items: [{ productId: product.id, quantity: 1 }],
        payments: [{ method: "cash", amount: 1000 }],
      };
      await post(members["CASHIER"]!.token, "/sales", sale).expect(201);
      await post(members["VIEWER"]!.token, "/sales", sale).expect(403);
      await post(members["STOCK_KEEPER"]!.token, "/sales", sale).expect(403);
    });

    it("la gestion des membres est réservée à OWNER/ADMIN", async () => {
      const path = `/businesses/${owner.businessId}/members`;
      await get(owner.token, path).expect(200);
      await get(members["ADMIN"]!.token, path).expect(200);
      for (const role of ["MANAGER", "CASHIER", "STOCK_KEEPER", "ACCOUNTANT", "VIEWER"]) {
        await get(members[role]!.token, path).expect(403);
      }
    });
  });

  describe("isolation entre entreprises", () => {
    it("un non-membre reçoit 404 (pas 403) sur les routes /businesses/:id — l'existence n'est pas révélée", async () => {
      await get(other.token, `/businesses/${owner.businessId}/members`).expect(404);
      await post(other.token, `/businesses/${owner.businessId}/activate`).expect(404);
      await post(other.token, `/businesses/${owner.businessId}/invitations`, {
        phone: uniquePhone(),
        roleCode: "VIEWER",
      }).expect(404);
    });

    it("un membre retiré perd l'accès immédiatement, même avec un jeton encore valide", async () => {
      const m = await invite("VIEWER");
      await get(m.token, "/products").expect(200);
      await h.sql.query(
        "DELETE FROM core.business_members WHERE business_id = $1 AND user_id = $2",
        [owner.businessId, m.session.userId],
      );
      const res = await get(m.token, "/products");
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe("NOT_A_MEMBER");
    });

    it("un membre suspendu perd l'accès", async () => {
      const m = await invite("VIEWER");
      await h.sql.query(
        "UPDATE core.business_members SET status = 'SUSPENDED' WHERE business_id = $1 AND user_id = $2",
        [owner.businessId, m.session.userId],
      );
      const res = await get(m.token, "/products");
      expect([403, 404]).toContain(res.status);
    });
  });

  describe("surcharges de permissions par membre", () => {
    let target: Member;
    const path = () =>
      `/businesses/${owner.businessId}/members/${target.session.userId}/permissions`;
    const put = (token: string, body: unknown) =>
      request(h.server)
        .put(`${API}${path()}`)
        .set(bearer(token))
        .send(body as object);

    beforeAll(async () => {
      target = await invite("CASHIER");
    });

    it("accorder une permission prend effet immédiatement, avec le même jeton", async () => {
      await post(target.token, "/products", { name: "Avant", salePrice: 1 }).expect(403);
      await put(owner.token, { overrides: { "products:manage": true } }).expect(200);
      await post(target.token, "/products", { name: "Après", salePrice: 1 }).expect(201);
    });

    it("retirer une permission du rôle prend effet immédiatement", async () => {
      await put(owner.token, { overrides: { "sales:create": false } }).expect(200);
      const product = (
        await post(owner.token, "/products", {
          name: "P",
          salePrice: 100,
          initialStock: 5,
        }).expect(201)
      ).body;
      await post(target.token, "/sales", {
        items: [{ productId: product.id, quantity: 1 }],
        payments: [{ method: "cash", amount: 100 }],
      }).expect(403);
    });

    it("la liste des membres expose les surcharges ; {} revient aux valeurs du rôle", async () => {
      const list = await get(owner.token, `/businesses/${owner.businessId}/members`).expect(200);
      const row = list.body.find((r: { userId: string }) => r.userId === target.session.userId);
      expect(row.permissionOverrides).toMatchObject({ "sales:create": false });

      await put(owner.token, { overrides: {} }).expect(200);
      await post(target.token, "/products", { name: "Retour", salePrice: 1 }).expect(403);
    });

    it("refuse les permissions inconnues et les valeurs non booléennes", async () => {
      const unknown = await put(owner.token, { overrides: { "nope:nope": true } });
      expect(unknown.status).toBe(400);
      expect(unknown.body.error.code).toBe("UNKNOWN_PERMISSION");
      await put(owner.token, { overrides: { "sales:create": "yes" } }).expect(400);
    });

    it("members:manage et subscription:manage ne sont jamais délégables", async () => {
      for (const code of ["members:manage", "subscription:manage"]) {
        const res = await put(owner.token, { overrides: { [code]: true } });
        expect(res.status).toBe(400);
        expect(res.body.error.code).toBe("PERMISSION_NOT_OVERRIDABLE");
      }
      await get(target.token, `/businesses/${owner.businessId}/members`).expect(403);
    });

    it("le propriétaire ne peut pas être restreint", async () => {
      const res = await request(h.server)
        .put(`${API}/businesses/${owner.businessId}/members/${owner.session.userId}/permissions`)
        .set(bearer(owner.token))
        .send({ overrides: { "sales:create": false } });
      expect(res.status).toBe(409);
      expect(res.body.error.code).toBe("OWNER_PERMISSIONS_FIXED");
    });

    it("un caissier ne peut pas modifier les permissions (les siennes ou celles d'un autre)", async () => {
      await put(target.token, { overrides: { "products:manage": true } }).expect(403);
    });

    it("changer le rôle prend effet immédiatement", async () => {
      const m = await invite("VIEWER");
      await post(m.token, "/products", { name: "X", salePrice: 1 }).expect(403);
      await request(h.server)
        .patch(`${API}/businesses/${owner.businessId}/members/${m.session.userId}`)
        .set(bearer(owner.token))
        .send({ roleCode: "MANAGER" })
        .expect(200);
      await post(m.token, "/products", { name: "X", salePrice: 1 }).expect(201);
    });
  });
});
