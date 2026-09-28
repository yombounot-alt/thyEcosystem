import pg from "pg";
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

/**
 * Gestion d'équipe de bout en bout : invitation → SMS → invitation visible dans l'app → acceptation,
 * refus, révocation, retrait, suspension, et les garde-fous (auto-modification, hiérarchie ADMIN,
 * isolation RLS des invitations).
 */
describe("Équipe — invitations et gestion des membres (e2e)", () => {
  let h: Harness;
  let owner: { session: Session; token: string; businessId: string };

  const get = (token: string, path: string) =>
    request(h.server).get(`${API}${path}`).set(bearer(token));
  const post = (token: string, path: string, body: object = {}) =>
    request(h.server).post(`${API}${path}`).set(bearer(token)).send(body);
  const put = (token: string, path: string, body: object) =>
    request(h.server).put(`${API}${path}`).set(bearer(token)).send(body);
  const del = (token: string, path: string) =>
    request(h.server).delete(`${API}${path}`).set(bearer(token));

  /** Invite `phone`, se connecte avec, accepte ; renvoie la session et un jeton sur l'entreprise. */
  async function join(roleCode: string, by = owner.token) {
    const phone = uniquePhone();
    const inv = await post(by, `/businesses/${owner.businessId}/invitations`, {
      phone,
      roleCode,
    }).expect(201);
    const session = await loginWithOtp(h, phone);
    await post(session.accessToken, `/me/invitations/${inv.body.id}/accept`).expect(200);
    const activated = await post(
      session.accessToken,
      `/businesses/${owner.businessId}/activate`,
    ).expect(200);
    return { phone, session, token: activated.body.accessToken as string };
  }

  beforeAll(async () => {
    h = await createHarness();
    await h.skipOutboxBacklog();
    const s = await loginWithOtp(h, uniquePhone());
    const b = await createBusiness(h, s, "Boutique Équipe");
    owner = { session: s, token: b.accessToken, businessId: b.businessId };
  });
  afterAll(async () => {
    await h.close();
  });

  describe("parcours d'invitation", () => {
    it("un numéro sans compte reçoit un SMS, puis trouve l'invitation à sa première connexion", async () => {
      const phone = uniquePhone();
      const inv = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone,
        roleCode: "CASHIER",
      }).expect(201);
      expect(inv.body).toMatchObject({ phone, roleCode: "CASHIER", status: "PENDING" });

      await h.drainOutbox();
      const sms = h.smsTo(phone);
      expect(sms).toHaveLength(1);
      expect(sms[0]).toContain("Boutique Équipe");
      expect(sms[0]).not.toMatch(/[A-Za-z0-9_-]{24,}/); // aucun secret dans le SMS

      const session = await loginWithOtp(h, phone);
      const mine = await get(session.accessToken, "/me/invitations").expect(200);
      expect(mine.body).toEqual([
        expect.objectContaining({
          id: inv.body.id,
          businessId: owner.businessId,
          businessName: "Boutique Équipe",
          roleCode: "CASHIER",
        }),
      ]);

      const accepted = await post(session.accessToken, `/me/invitations/${inv.body.id}/accept`);
      expect(accepted.status).toBe(200);
      expect(accepted.body).toEqual({ businessId: owner.businessId, roleCode: "CASHIER" });
      await get(session.accessToken, "/me/invitations").expect(200, []);

      const me = await get(session.accessToken, "/me").expect(200);
      expect(me.body.businesses.map((b: { id: string }) => b.id)).toContain(owner.businessId);
    });

    it("une invitation n'est visible que par le numéro invité, et par l'entreprise", async () => {
      const phone = uniquePhone();
      await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone,
        roleCode: "VIEWER",
      }).expect(201);
      const stranger = await loginWithOtp(h, uniquePhone());
      await get(stranger.accessToken, "/me/invitations").expect(200, []);

      const list = await get(owner.token, `/businesses/${owner.businessId}/invitations`).expect(
        200,
      );
      expect(list.body.map((i: { phone: string }) => i.phone)).toContain(phone);
    });

    it("RLS : sous le rôle applicatif, une autre entreprise ne voit aucune invitation", async () => {
      const other = await createBusiness(h, await loginWithOtp(h, uniquePhone()), "Autre");
      await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone: uniquePhone(),
        roleCode: "VIEWER",
      }).expect(201);
      const app = new pg.Client({ connectionString: h.cfg.databaseUrl });
      await app.connect();
      try {
        await app.query("BEGIN");
        await app.query("SELECT set_config('app.business_id', $1, true)", [other.businessId]);
        const r = await app.query(
          "SELECT count(*)::int AS n FROM core.business_invitations WHERE business_id = $1",
          [owner.businessId],
        );
        expect(r.rows[0].n).toBe(0);
        await app.query("ROLLBACK");
        const none = await app.query("SELECT count(*)::int AS n FROM core.business_invitations");
        expect(none.rows[0].n).toBe(0); // sans contexte : rien (fail-closed)
      } finally {
        await app.end();
      }
    });

    it("refuser une invitation la retire, sans créer d'adhésion", async () => {
      const phone = uniquePhone();
      const inv = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone,
        roleCode: "VIEWER",
      }).expect(201);
      const session = await loginWithOtp(h, phone);
      await post(session.accessToken, `/me/invitations/${inv.body.id}/decline`).expect(204);
      await get(session.accessToken, "/me/invitations").expect(200, []);
      await post(session.accessToken, `/businesses/${owner.businessId}/activate`).expect(404);
    });

    it("révoquer une invitation empêche son acceptation", async () => {
      const phone = uniquePhone();
      const inv = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone,
        roleCode: "VIEWER",
      }).expect(201);
      await del(owner.token, `/businesses/${owner.businessId}/invitations/${inv.body.id}`).expect(
        204,
      );
      const session = await loginWithOtp(h, phone);
      const res = await post(session.accessToken, `/me/invitations/${inv.body.id}/accept`);
      expect(res.status).toBe(422);
      expect(res.body.error.code).toBe("INVITATION_INVALID");
    });

    it("réinviter le même numéro remplace l'invitation en attente (une seule visible)", async () => {
      const phone = uniquePhone();
      await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone,
        roleCode: "VIEWER",
      }).expect(201);
      const second = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone,
        roleCode: "MANAGER",
      }).expect(201);
      const session = await loginWithOtp(h, phone);
      const mine = await get(session.accessToken, "/me/invitations").expect(200);
      expect(mine.body).toHaveLength(1);
      expect(mine.body[0]).toMatchObject({ id: second.body.id, roleCode: "MANAGER" });
    });

    it("inviter un membre existant est refusé", async () => {
      const m = await join("VIEWER");
      const res = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone: m.phone,
        roleCode: "CASHIER",
      });
      expect(res.status).toBe(409);
      expect(res.body.error.code).toBe("ALREADY_MEMBER");
    });

    it("une invitation expirée ne peut plus être acceptée", async () => {
      const phone = uniquePhone();
      const inv = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone,
        roleCode: "VIEWER",
      }).expect(201);
      await h.sql.query(
        "UPDATE core.business_invitations SET expires_at = now() - interval '1 minute' WHERE id = $1",
        [inv.body.id],
      );
      const session = await loginWithOtp(h, phone);
      await get(session.accessToken, "/me/invitations").expect(200, []);
      const res = await post(session.accessToken, `/me/invitations/${inv.body.id}/accept`);
      expect(res.status).toBe(422);
      expect(res.body.error.code).toBe("INVITATION_EXPIRED");
    });
  });

  describe("gestion des membres", () => {
    it("retirer un membre coupe son accès immédiatement ; il peut être réinvité", async () => {
      const m = await join("CASHIER");
      await get(m.token, "/products").expect(200);
      await del(owner.token, `/businesses/${owner.businessId}/members/${m.session.userId}`).expect(
        204,
      );
      const res = await get(m.token, "/products");
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe("NOT_A_MEMBER");

      const members = await get(owner.token, `/businesses/${owner.businessId}/members`).expect(200);
      expect(members.body.map((r: { userId: string }) => r.userId)).not.toContain(m.session.userId);

      const again = await post(owner.token, `/businesses/${owner.businessId}/invitations`, {
        phone: m.phone,
        roleCode: "VIEWER",
      }).expect(201);
      await post(m.session.accessToken, `/me/invitations/${again.body.id}/accept`).expect(200);
      const back = await post(
        m.session.accessToken,
        `/businesses/${owner.businessId}/activate`,
      ).expect(200);
      expect(back.body.role).toBe("VIEWER");
    });

    it("suspendre puis réactiver un membre", async () => {
      const m = await join("CASHIER");
      const path = `/businesses/${owner.businessId}/members/${m.session.userId}/status`;
      await put(owner.token, path, { status: "SUSPENDED" }).expect(200);
      expect((await get(m.token, "/products")).status).toBe(403);
      await put(owner.token, path, { status: "ACTIVE" }).expect(200);
      await get(m.token, "/products").expect(200);
    });

    it("personne ne modifie son propre accès", async () => {
      const admin = await join("ADMIN");
      const self = await request(h.server)
        .patch(`${API}/businesses/${owner.businessId}/members/${admin.session.userId}`)
        .set(bearer(admin.token))
        .send({ roleCode: "VIEWER" });
      expect(self.status).toBe(403);
      expect(self.body.error.code).toBe("SELF_MODIFICATION");
    });

    it("un ADMIN gère l'équipe mais ni les administrateurs, ni le propriétaire", async () => {
      const admin = await join("ADMIN");
      const otherAdmin = await join("ADMIN");
      const cashier = await join("CASHIER");

      // Il peut inviter et gérer les rôles « ordinaires »…
      await post(admin.token, `/businesses/${owner.businessId}/invitations`, {
        phone: uniquePhone(),
        roleCode: "CASHIER",
      }).expect(201);
      await request(h.server)
        .patch(`${API}/businesses/${owner.businessId}/members/${cashier.session.userId}`)
        .set(bearer(admin.token))
        .send({ roleCode: "MANAGER" })
        .expect(200);

      // …mais pas nommer, modifier ou retirer un administrateur, ni toucher au propriétaire.
      const promote = await request(h.server)
        .patch(`${API}/businesses/${owner.businessId}/members/${cashier.session.userId}`)
        .set(bearer(admin.token))
        .send({ roleCode: "ADMIN" });
      expect(promote.body.error.code).toBe("OWNER_ONLY");
      const inviteAdmin = await post(admin.token, `/businesses/${owner.businessId}/invitations`, {
        phone: uniquePhone(),
        roleCode: "ADMIN",
      });
      expect(inviteAdmin.body.error.code).toBe("OWNER_ONLY");
      const removeAdmin = await del(
        admin.token,
        `/businesses/${owner.businessId}/members/${otherAdmin.session.userId}`,
      );
      expect(removeAdmin.body.error.code).toBe("OWNER_ONLY");
      const removeOwner = await del(
        admin.token,
        `/businesses/${owner.businessId}/members/${owner.session.userId}`,
      );
      expect(removeOwner.status).toBe(409);
      expect(removeOwner.body.error.code).toBe("OWNER_IMMUTABLE");
    });

    it("chaque action sensible laisse une trace d'audit", async () => {
      const m = await join("VIEWER");
      await request(h.server)
        .patch(`${API}/businesses/${owner.businessId}/members/${m.session.userId}`)
        .set(bearer(owner.token))
        .send({ roleCode: "CASHIER" })
        .expect(200);
      await del(owner.token, `/businesses/${owner.businessId}/members/${m.session.userId}`).expect(
        204,
      );
      const rows = await h.sql.query<{ action: string; actor_id: string }>(
        `SELECT action, actor_id FROM ops.audit_logs
          WHERE target_id = $1 OR metadata->>'businessId' = $2 AND actor_id = $3
          ORDER BY id`,
        [m.session.userId, owner.businessId, m.session.userId],
      );
      const actions = rows.rows.map((r) => r.action);
      expect(actions).toEqual(
        expect.arrayContaining(["invitation.accept", "member.role_change", "member.remove"]),
      );
    });
  });

  describe("fiche de l'entreprise", () => {
    it("business:settings modifie la fiche ; un caissier ne peut pas", async () => {
      const cashier = await join("CASHIER");
      const updated = await request(h.server)
        .patch(`${API}/businesses/${owner.businessId}`)
        .set(bearer(owner.token))
        .send({ address: "Kaloum, Conakry", phone: "+224622111111" })
        .expect(200);
      expect(updated.body).toMatchObject({ address: "Kaloum, Conakry", phone: "+224622111111" });
      await request(h.server)
        .patch(`${API}/businesses/${owner.businessId}`)
        .set(bearer(cashier.token))
        .send({ name: "Piratée" })
        .expect(403);
      // Devise et pays sont figés (propriétés inconnues ⇒ 400).
      await request(h.server)
        .patch(`${API}/businesses/${owner.businessId}`)
        .set(bearer(owner.token))
        .send({ currency: "EUR" })
        .expect(400);
    });
  });
});
