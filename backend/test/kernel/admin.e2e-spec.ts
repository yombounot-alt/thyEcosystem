import request from "supertest";
import type TestAgent from "supertest/lib/agent.js";
import { base32Decode, hotp, totpStep } from "../../src/modules/admin/totp.js";
import { CryptoService } from "../../src/kernel/security/crypto.service.js";
import {
  API,
  createBusiness,
  createHarness,
  loginWithOtp,
  uniquePhone,
  type Harness,
} from "../harness.js";

const ADMIN = "/admin/v1";
let seq = 0;

interface StaffAccount {
  id: string;
  email: string;
  password: string;
}

interface StaffSession {
  agent: TestAgent;
  csrf: string;
  secret: Buffer;
}

/**
 * Console d'administration (L0.11) de bout en bout : connexion + double authentification TOTP,
 * sessions, anti-CSRF, verrouillage, matrice rôle × droit, actions support (motivées, auditées,
 * effectives dans l'app), réglages, et étanchéité totale entre comptes clients et staff.
 */
describe("Admin (e2e)", () => {
  let h: Harness;

  beforeAll(async () => {
    h = await createHarness();
  });
  afterAll(async () => {
    await h.close();
  });

  async function createStaff(role: string): Promise<StaffAccount> {
    const email = `staff${Date.now()}${++seq}@thy.test`;
    const password = `Mdp-${Date.now()}-${seq}-solide`;
    const hash = await h.app.get(CryptoService).hashPassword(password);
    const r = await h.sql.query<{ id: string }>(
      `WITH s AS (INSERT INTO core.staff_users (email, password_hash, full_name)
                  VALUES ($1, $2, 'Staff Test') RETURNING id)
       INSERT INTO core.staff_role_assignments (staff_id, role_id)
       SELECT s.id, r.id FROM s, core.roles r WHERE r.scope = 'PLATFORM' AND r.code = $3
       RETURNING staff_id AS id`,
      [email, hash, role],
    );
    return { id: r.rows[0]!.id, email, password };
  }

  const code = (secret: Buffer, offset = 0) => hotp(secret, totpStep(Date.now()) + offset);

  /** Connexion complète : mot de passe, enrôlement TOTP, premier code. */
  async function signIn(staff: StaffAccount): Promise<StaffSession> {
    const agent = request.agent(h.server);
    const login = await agent
      .post(`${ADMIN}/auth/login`)
      .send({ email: staff.email, password: staff.password })
      .expect(200);
    expect(login.body.next).toBe("enroll_totp");
    const csrf = login.body.csrfToken as string;
    const setup = await agent
      .post(`${ADMIN}/auth/totp/setup`)
      .set("x-csrf-token", csrf)
      .expect(200);
    const secret = base32Decode(setup.body.secret as string);
    await agent
      .post(`${ADMIN}/auth/totp/confirm`)
      .set("x-csrf-token", csrf)
      .send({ code: code(secret) })
      .expect(204);
    return { agent, csrf, secret };
  }

  describe("connexion et double authentification", () => {
    it("mot de passe faux ou compte inconnu : même réponse, sans indice", async () => {
      const staff = await createStaff("ADMIN");
      const wrong = await request(h.server)
        .post(`${ADMIN}/auth/login`)
        .send({ email: staff.email, password: "pas-le-bon" });
      const unknown = await request(h.server)
        .post(`${ADMIN}/auth/login`)
        .send({ email: "personne@thy.test", password: "pas-le-bon" });
      expect(wrong.status).toBe(401);
      expect(unknown.status).toBe(401);
      expect(wrong.body.error.code).toBe(unknown.body.error.code);
    });

    it("rien n'est accessible avant la double authentification ; l'enrôlement l'active", async () => {
      const staff = await createStaff("ADMIN");
      const agent = request.agent(h.server);
      const login = await agent
        .post(`${ADMIN}/auth/login`)
        .send({ email: staff.email.toUpperCase(), password: staff.password })
        .expect(200);
      const csrf = login.body.csrfToken as string;
      const cookie = login.headers["set-cookie"]?.[0] ?? "";
      expect(cookie).toMatch(/thy_admin_session=.+; Max-Age=\d+; Path=\/admin\/v1; .*HttpOnly/);
      expect(cookie).toMatch(/SameSite=Strict/);

      const blocked = await agent.get(`${ADMIN}/audit`);
      expect(blocked.status).toBe(401);
      expect(blocked.body.error.code).toBe("STAFF_MFA_REQUIRED");

      const setup = await agent
        .post(`${ADMIN}/auth/totp/setup`)
        .set("x-csrf-token", csrf)
        .expect(200);
      expect(setup.body.otpauthUri).toMatch(/^otpauth:\/\/totp\/THY%20Admin/);
      const secret = base32Decode(setup.body.secret as string);
      const stored = await h.sql.query(
        "SELECT totp_secret_enc FROM core.staff_users WHERE id = $1",
        [staff.id],
      );
      expect((stored.rows[0].totp_secret_enc as Buffer).includes(secret)).toBe(false); // chiffré

      const bad = await agent
        .post(`${ADMIN}/auth/totp/confirm`)
        .set("x-csrf-token", csrf)
        .send({ code: code(secret) === "000000" ? "111111" : "000000" });
      expect(bad.status).toBe(401);
      await agent
        .post(`${ADMIN}/auth/totp/confirm`)
        .set("x-csrf-token", csrf)
        .send({ code: code(secret) })
        .expect(204);

      const session = await agent.get(`${ADMIN}/auth/session`).expect(200);
      expect(session.body).toMatchObject({ mfaVerified: true, mfaEnrollmentRequired: false });
      expect(session.body.staff.roles).toEqual(["ADMIN"]);
      await agent.get(`${ADMIN}/audit`).expect(200);

      const audit = await h.sql.query<{ action: string }>(
        "SELECT action FROM ops.audit_logs WHERE actor_id = $1 AND actor_type = 'staff' ORDER BY id",
        [staff.id],
      );
      expect(audit.rows.map((r) => r.action)).toEqual(
        expect.arrayContaining(["staff.login_failed", "staff.totp_enabled", "staff.login"]),
      );
    });

    it("à la connexion suivante, un code déjà utilisé est refusé (anti-rejeu)", async () => {
      const staff = await createStaff("ADMIN");
      const first = await signIn(staff);
      const used = code(first.secret);
      const agent = request.agent(h.server);
      const login = await agent
        .post(`${ADMIN}/auth/login`)
        .send({ email: staff.email, password: staff.password })
        .expect(200);
      expect(login.body.next).toBe("verify_totp");
      const replay = await agent
        .post(`${ADMIN}/auth/totp/confirm`)
        .set("x-csrf-token", login.body.csrfToken)
        .send({ code: used });
      expect(replay.status).toBe(401);
      expect(replay.body.error.code).toBe("STAFF_INVALID_TOTP");
      await agent
        .post(`${ADMIN}/auth/totp/confirm`)
        .set("x-csrf-token", login.body.csrfToken)
        .send({ code: code(first.secret, 1) })
        .expect(204);
    });

    it("verrouillage après 5 échecs, même avec le bon mot de passe ensuite", async () => {
      const staff = await createStaff("ADMIN");
      for (let i = 0; i < 5; i++) {
        await request(h.server)
          .post(`${ADMIN}/auth/login`)
          .send({ email: staff.email, password: "mauvais" })
          .expect(401);
      }
      const locked = await request(h.server)
        .post(`${ADMIN}/auth/login`)
        .send({ email: staff.email, password: staff.password });
      expect(locked.status).toBe(423);
      expect(locked.body.error.code).toBe("STAFF_LOCKED");
    });

    it("anti-CSRF : une action sans jeton (ou avec un jeton faux) est refusée", async () => {
      const s = await signIn(await createStaff("SUPER_ADMIN"));
      const none = await s.agent.post(`${ADMIN}/auth/logout`);
      expect(none.status).toBe(403);
      expect(none.body.error.code).toBe("CSRF_INVALID");
      await s.agent.post(`${ADMIN}/auth/logout`).set("x-csrf-token", "faux-jeton").expect(403);

      // Le jeton rendu par /session remplace l'ancien.
      const rotated = (await s.agent.get(`${ADMIN}/auth/session`).expect(200)).body.csrfToken;
      await s.agent.post(`${ADMIN}/auth/logout`).set("x-csrf-token", s.csrf).expect(403);
      await s.agent.post(`${ADMIN}/auth/logout`).set("x-csrf-token", rotated).expect(204);
      await s.agent.get(`${ADMIN}/auth/session`).expect(401); // déconnecté
    });

    it("une session inactive trop longtemps expire", async () => {
      const staff = await createStaff("ADMIN");
      const s = await signIn(staff);
      await h.sql.query(
        "UPDATE core.staff_sessions SET last_seen_at = now() - interval '2 hours' WHERE staff_id = $1",
        [staff.id],
      );
      const res = await s.agent.get(`${ADMIN}/auth/session`);
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe("STAFF_SESSION_EXPIRED");
    });
  });

  describe("étanchéité clients / staff", () => {
    it("un jeton client n'ouvre pas l'admin ; une session staff n'ouvre pas l'app", async () => {
      const client = await loginWithOtp(h, uniquePhone());
      const res = await request(h.server)
        .get(`${ADMIN}/users`)
        .set("Authorization", `Bearer ${client.accessToken}`);
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe("STAFF_UNAUTHENTICATED");

      const s = await signIn(await createStaff("SUPER_ADMIN"));
      await s.agent.get(`${API}/me`).expect(401);
    });

    it("l'admin est servi sous /admin/v1 uniquement, et absent du contrat OpenAPI public", async () => {
      await request(h.server).get(`${API}/admin/v1/auth/session`).expect(404);
      const spec = await request(h.server).get(`${API}/openapi.json`).expect(200);
      expect(Object.keys(spec.body.paths as object).some((p) => p.includes("admin"))).toBe(false);
    });
  });

  describe("droits par rôle", () => {
    it("SUPPORT_AGENT : utilisateurs (dont numéro en clair) ; pas d'audit ni de réglages", async () => {
      const s = await signIn(await createStaff("SUPPORT_AGENT"));
      await s.agent.get(`${ADMIN}/users`).expect(200);
      const audit = await s.agent.get(`${ADMIN}/audit`);
      expect(audit.status).toBe(403);
      expect(audit.body.error.code).toBe("ADMIN_FORBIDDEN");
      await s.agent.get(`${ADMIN}/settings/flags`).expect(403);
    });

    it("ADMIN : audit et réglages ; ni numéro en clair ni suspension", async () => {
      const client = await loginWithOtp(h, uniquePhone());
      const s = await signIn(await createStaff("ADMIN"));
      await s.agent.get(`${ADMIN}/audit`).expect(200);
      await s.agent.get(`${ADMIN}/settings/flags`).expect(200);
      await s.agent
        .post(`${ADMIN}/users/${client.userId}/reveal-phone`)
        .set("x-csrf-token", s.csrf)
        .send({ reason: "vérification du support" })
        .expect(403);
      await s.agent
        .post(`${ADMIN}/users/${client.userId}/suspend`)
        .set("x-csrf-token", s.csrf)
        .send({ reason: "test de droits" })
        .expect(403);
    });

    it("un compte staff sans rôle ne peut rien consulter", async () => {
      const email = `norole${Date.now()}@thy.test`;
      const password = "Mdp-sans-role-solide";
      const hash = await h.app.get(CryptoService).hashPassword(password);
      await h.sql.query(
        "INSERT INTO core.staff_users (email, password_hash, full_name) VALUES ($1, $2, 'Sans rôle')",
        [email, hash],
      );
      const s = await signIn({ id: "", email, password });
      await s.agent.get(`${ADMIN}/users`).expect(403);
    });
  });

  describe("utilisateurs (support)", () => {
    let support: StaffSession;
    let supportId: string;
    beforeAll(async () => {
      const staff = await createStaff("SUPPORT_AGENT");
      supportId = staff.id;
      support = await signIn(staff);
    });

    it("recherche par début de numéro : numéros masqués, fiche avec entreprises et sessions", async () => {
      const phone = uniquePhone();
      const client = await loginWithOtp(h, phone);
      const b = await createBusiness(h, client, "Boutique Support");
      const found = await support.agent.get(
        `${ADMIN}/users?q=${encodeURIComponent(phone.slice(0, 11))}`,
      );
      expect(found.status).toBe(200);
      const row = (found.body.items as { id: string; phoneMasked: string }[]).find(
        (u) => u.id === client.userId,
      );
      expect(row?.phoneMasked).toMatch(/^\+224•+\d{2}$/);
      expect(JSON.stringify(found.body)).not.toContain(phone);

      const detail = await support.agent.get(`${ADMIN}/users/${client.userId}`).expect(200);
      expect(detail.body.businesses).toEqual([
        expect.objectContaining({ id: b.businessId, name: "Boutique Support", roleCode: "OWNER" }),
      ]);
      expect(detail.body.activeSessions.length).toBeGreaterThanOrEqual(1);
      expect(JSON.stringify(detail.body)).not.toContain(phone);
    });

    it("afficher un numéro en clair exige un motif et laisse une trace", async () => {
      const phone = uniquePhone();
      const client = await loginWithOtp(h, phone);
      await support.agent
        .post(`${ADMIN}/users/${client.userId}/reveal-phone`)
        .set("x-csrf-token", support.csrf)
        .send({})
        .expect(400);
      const res = await support.agent
        .post(`${ADMIN}/users/${client.userId}/reveal-phone`)
        .set("x-csrf-token", support.csrf)
        .send({ reason: "rappel demandé par le client" })
        .expect(200);
      expect(res.body.phone).toBe(phone);
      const audit = await h.sql.query(
        `SELECT metadata FROM ops.audit_logs
          WHERE action = 'admin.user.reveal_phone' AND actor_id = $1 AND target_id = $2`,
        [supportId, client.userId],
      );
      expect(audit.rows[0]?.metadata).toEqual({ reason: "rappel demandé par le client" });
    });

    it("suspendre met le compte en lecture seule dans l'app ; réactiver le rétablit", async () => {
      const client = await loginWithOtp(h, uniquePhone());
      await support.agent
        .post(`${ADMIN}/users/${client.userId}/suspend`)
        .set("x-csrf-token", support.csrf)
        .send({ reason: "fraude suspectée" })
        .expect(200);
      const blocked = await request(h.server)
        .patch(`${API}/me`)
        .set("Authorization", `Bearer ${client.accessToken}`)
        .send({ fullName: "Essai" });
      expect(blocked.status).toBe(403);
      expect(blocked.body.error.code).toBe("ACCOUNT_RESTRICTED");
      // Lecture toujours possible.
      await request(h.server)
        .get(`${API}/me`)
        .set("Authorization", `Bearer ${client.accessToken}`)
        .expect(200);

      await support.agent
        .post(`${ADMIN}/users/${client.userId}/reactivate`)
        .set("x-csrf-token", support.csrf)
        .send({ reason: "vérification faite" })
        .expect(200);
      await request(h.server)
        .patch(`${API}/me`)
        .set("Authorization", `Bearer ${client.accessToken}`)
        .send({ fullName: "Essai" })
        .expect(200);
    });

    it("révoquer les sessions déconnecte tous les appareils immédiatement", async () => {
      const client = await loginWithOtp(h, uniquePhone());
      const res = await support.agent
        .post(`${ADMIN}/users/${client.userId}/revoke-sessions`)
        .set("x-csrf-token", support.csrf)
        .send({ reason: "téléphone volé" })
        .expect(200);
      expect(res.body.revokedTokens).toBeGreaterThanOrEqual(1);
      await request(h.server)
        .get(`${API}/me`)
        .set("Authorization", `Bearer ${client.accessToken}`)
        .expect(401);
      await request(h.server)
        .post(`${API}/auth/refresh`)
        .send({ refreshToken: client.refreshToken })
        .expect(401);
    });
  });

  describe("réglages", () => {
    it("un flag modifié par l'admin s'applique aux utilisateurs, avec son historique", async () => {
      const staff = await createStaff("ADMIN");
      const s = await signIn(staff);
      const key = `test.admin_${Date.now()}`;
      await s.agent
        .put(`${ADMIN}/settings/flags/${key}`)
        .set("x-csrf-token", s.csrf)
        .send({
          description: "Essai admin",
          enabled: true,
          rolloutPercent: 100,
          reason: "test e2e",
        })
        .expect(200);
      const client = await loginWithOtp(h, uniquePhone());
      const flags = await request(h.server)
        .get(`${API}/me/feature-flags`)
        .set("Authorization", `Bearer ${client.accessToken}`)
        .expect(200);
      expect(flags.body.flags).toContain(key);
      const audit = await h.sql.query(
        "SELECT metadata FROM ops.audit_logs WHERE action = 'admin.flag.update' AND target_id = $1",
        [key],
      );
      expect(audit.rows[0]?.metadata).toMatchObject({ reason: "test e2e", before: null });
      await h.sql.query("DELETE FROM ops.feature_flags WHERE key = $1", [key]);
    });

    it("une dérogation d'offre (ex. membres) s'applique immédiatement à l'entreprise", async () => {
      const s = await signIn(await createStaff("ADMIN"));
      const owner = await loginWithOtp(h, uniquePhone());
      const b = await createBusiness(h, owner, "Pilote", { freePlan: true });

      const found = await s.agent.get(`${ADMIN}/businesses?q=${b.businessId}`).expect(200);
      expect(found.body[0]).toMatchObject({ id: b.businessId, planCode: "FREE", members: 1 });

      const set = await s.agent
        .put(`${ADMIN}/businesses/${b.businessId}/entitlements/members.max`)
        .set("x-csrf-token", s.csrf)
        .send({ value: 10, reason: "pilote de lancement" })
        .expect(200);
      expect(
        (set.body.entitlements as { code: string; overrideValue: number }[]).find(
          (e) => e.code === "members.max",
        )?.overrideValue,
      ).toBe(10);
      const summary = await request(h.server)
        .get(`${API}/businesses/${b.businessId}/subscription`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .expect(200);
      expect(summary.body.entitlements["members.max"]).toBe(10);

      await s.agent
        .delete(`${ADMIN}/businesses/${b.businessId}/entitlements/members.max`)
        .set("x-csrf-token", s.csrf)
        .send({ reason: "fin du pilote" })
        .expect(200);
      const after = await request(h.server)
        .get(`${API}/businesses/${b.businessId}/subscription`)
        .set("Authorization", `Bearer ${b.accessToken}`)
        .expect(200);
      expect(after.body.entitlements["members.max"]).toBe(3);

      const history = await h.sql.query<{ type: string }>(
        "SELECT type FROM sub.subscription_events WHERE business_id = $1 ORDER BY id",
        [b.businessId],
      );
      expect(history.rows.map((r) => r.type)).toEqual([
        "STARTED",
        "OVERRIDE_SET",
        "OVERRIDE_REMOVED",
      ]);
    });

    it("le journal d'audit se filtre par action et identifie l'auteur staff", async () => {
      const staff = await createStaff("SUPER_ADMIN");
      const s = await signIn(staff);
      const res = await s.agent
        .get(`${ADMIN}/audit?action=staff.login&actorId=${staff.id}`)
        .expect(200);
      expect(res.body.items[0]).toMatchObject({
        action: "staff.login",
        actorType: "staff",
        actorLabel: staff.email,
      });
    });
  });
});
