import request from "supertest";
import { OutboxRelayService } from "../../src/kernel/events/outbox-relay.service.js";
import {
  API,
  createBusiness,
  createHarness,
  loginWithOtp,
  uniquePhone,
  type Harness,
} from "../harness.js";

const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });

interface Notification {
  id: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, string>;
  readAt: string | null;
}

describe("Notifications — outbox → boîte in-app + push (e2e)", () => {
  let h: Harness;
  const get = (token: string, path: string) =>
    request(h.server).get(`${API}${path}`).set(bearer(token));
  const post = (token: string, path: string, body: object = {}) =>
    request(h.server).post(`${API}${path}`).set(bearer(token)).send(body);
  const inbox = async (token: string) =>
    (await get(token, "/me/notifications").expect(200)).body.items as Notification[];

  beforeAll(async () => {
    h = await createHarness();
    await h.skipOutboxBacklog();
  });
  afterAll(async () => {
    await h.close();
  });

  it("créer une entreprise envoie une notification de bienvenue (une seule, même si l'événement est rejoué)", async () => {
    const s = await loginWithOtp(h, uniquePhone());
    const b = await createBusiness(h, s, "Chez Fanta");
    expect(await inbox(s.accessToken)).toEqual([]); // rien avant le passage du relais

    await h.drainOutbox();
    const items = await inbox(s.accessToken);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      type: "BUSINESS_WELCOME",
      title: "Bienvenue sur THY",
      data: { businessId: b.businessId, businessName: "Chez Fanta", type: "BUSINESS_WELCOME" },
      readAt: null,
    });
    expect(items[0]!.body).toContain("Chez Fanta");

    // Rejeu « au moins une fois » : on remet l'événement en file, rien ne doit être dupliqué.
    await h.sql.query(
      `UPDATE ops.outbox_events SET published_at = NULL, next_attempt_at = now()
        WHERE event_type = 'BUSINESS_CREATED' AND business_id = $1`,
      [b.businessId],
    );
    await h.sql.query(
      `DELETE FROM ops.processed_events WHERE event_id IN
         (SELECT id FROM ops.outbox_events WHERE business_id = $1)`,
      [b.businessId],
    );
    await h.drainOutbox();
    expect(await inbox(s.accessToken)).toHaveLength(1);
  });

  it("compteur de non-lus, lecture unitaire et « tout marquer comme lu »", async () => {
    const s = await loginWithOtp(h, uniquePhone());
    const b = await createBusiness(h, s, "Compteur");
    const phone = uniquePhone();
    const inv = await post(b.accessToken, `/businesses/${b.businessId}/invitations`, {
      phone,
      roleCode: "CASHIER",
    }).expect(201);
    const member = await loginWithOtp(h, phone);
    await post(member.accessToken, `/me/invitations/${inv.body.id}/accept`).expect(200);
    await h.drainOutbox();

    // Le propriétaire : bienvenue + « nouveau membre ».
    const unread = await get(b.accessToken, "/me/notifications/unread-count").expect(200);
    expect(unread.body.unread).toBe(2);
    const items = await inbox(b.accessToken);
    expect(items.map((n) => n.type)).toEqual(["TEAM_MEMBER_JOINED", "BUSINESS_WELCOME"]);
    expect(items[0]!.body).toContain("caissier");

    await post(b.accessToken, `/me/notifications/${items[0]!.id}/read`).expect(200);
    expect((await get(b.accessToken, "/me/notifications/unread-count")).body.unread).toBe(1);
    const all = await post(b.accessToken, "/me/notifications/read-all").expect(200);
    expect(all.body.updated).toBe(1);
    expect((await get(b.accessToken, "/me/notifications/unread-count")).body.unread).toBe(0);

    // Le nouveau membre a été prévenu de son arrivée.
    expect((await inbox(member.accessToken)).map((n) => n.type)).toContain("MEMBER_JOINED");
  });

  it("personne ne lit ni ne marque la notification d'un autre (404)", async () => {
    const a = await loginWithOtp(h, uniquePhone());
    await createBusiness(h, a, "A");
    const bUser = await loginWithOtp(h, uniquePhone());
    await h.drainOutbox();
    const [mine] = await inbox(a.accessToken);
    await post(bUser.accessToken, `/me/notifications/${mine!.id}/read`).expect(404);
  });

  it("un utilisateur déjà inscrit reçoit l'invitation dans sa boîte", async () => {
    const owner = await loginWithOtp(h, uniquePhone());
    const b = await createBusiness(h, owner, "Invitante");
    const phone = uniquePhone();
    const invitee = await loginWithOtp(h, phone);
    await post(b.accessToken, `/businesses/${b.businessId}/invitations`, {
      phone,
      roleCode: "VIEWER",
    }).expect(201);
    await h.drainOutbox();
    const items = await inbox(invitee.accessToken);
    expect(items[0]).toMatchObject({
      type: "BUSINESS_INVITATION",
      data: expect.objectContaining({ businessId: b.businessId }) as unknown,
    });
    expect(items[0]!.body).toContain("Invitante");
    expect(items[0]!.body).toContain("lecteur");
  });

  it("pagination par curseur", async () => {
    const s = await loginWithOtp(h, uniquePhone());
    for (let i = 0; i < 3; i++) await createBusiness(h, s, `Page ${i}`);
    await h.drainOutbox();
    const first = await get(s.accessToken, "/me/notifications?limit=2").expect(200);
    expect(first.body.items).toHaveLength(2);
    expect(first.body.nextCursor).toEqual(expect.any(String));
    const second = await get(
      s.accessToken,
      `/me/notifications?limit=2&cursor=${first.body.nextCursor}`,
    ).expect(200);
    expect(second.body.items).toHaveLength(1);
    expect(second.body.nextCursor).toBeNull();
    const ids = [...first.body.items, ...second.body.items].map((n: Notification) => n.id);
    expect(new Set(ids).size).toBe(3);
  });

  describe("push", () => {
    it("envoie un push aux appareils enregistrés et respecte les préférences", async () => {
      const s = await loginWithOtp(h, uniquePhone());
      const token = `fcm-${"a".repeat(30)}-${Date.now()}`;
      await post(s.accessToken, "/me/devices", { token, platform: "android" }).expect(204);

      await createBusiness(h, s, "Push 1");
      await h.drainOutbox();
      const sent = h.pushes.filter((p) => p.tokens.includes(token));
      expect(sent).toHaveLength(1);
      expect(sent[0]!.message).toMatchObject({
        title: "Bienvenue sur THY",
        data: expect.objectContaining({ type: "BUSINESS_WELCOME" }) as unknown,
      });

      // Couper le push de bienvenue : la boîte in-app garde la trace, le push n'part plus.
      const prefs = await request(h.server)
        .put(`${API}/me/notification-preferences`)
        .set(bearer(s.accessToken))
        .send({ push: { BUSINESS_WELCOME: false } })
        .expect(200);
      expect(prefs.body).toContainEqual({ type: "BUSINESS_WELCOME", push: false });
      await createBusiness(h, s, "Push 2");
      await h.drainOutbox();
      expect(h.pushes.filter((p) => p.tokens.includes(token))).toHaveLength(1);
      expect(
        (await inbox(s.accessToken)).filter((n) => n.type === "BUSINESS_WELCOME"),
      ).toHaveLength(2);
    });

    it("les notifications de sécurité ne sont pas désactivables", async () => {
      const s = await loginWithOtp(h, uniquePhone());
      const res = await request(h.server)
        .put(`${API}/me/notification-preferences`)
        .set(bearer(s.accessToken))
        .send({ push: { SECURITY_SESSION_REVOKED: false } });
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe("NOTIFICATION_MANDATORY");
    });

    it("un jeton repris par un autre compte n'appartient plus à l'ancien ; un jeton invalide est révoqué", async () => {
      const a = await loginWithOtp(h, uniquePhone());
      const b = await loginWithOtp(h, uniquePhone());
      const shared = `fcm-shared-${"b".repeat(30)}-${Date.now()}`;
      await post(a.accessToken, "/me/devices", { token: shared, platform: "android" }).expect(204);
      await post(b.accessToken, "/me/devices", { token: shared, platform: "android" }).expect(204);
      const owners = await h.sql.query("SELECT user_id FROM ntf.device_tokens WHERE token = $1", [
        shared,
      ]);
      expect(owners.rows).toEqual([{ user_id: b.userId }]);

      const invalid = `invalid-${"c".repeat(30)}-${Date.now()}`;
      await post(a.accessToken, "/me/devices", { token: invalid, platform: "ios" }).expect(204);
      await createBusiness(h, a, "Jeton");
      await h.drainOutbox();
      const row = await h.sql.query("SELECT revoked_at FROM ntf.device_tokens WHERE token = $1", [
        invalid,
      ]);
      expect(row.rows[0].revoked_at).not.toBeNull();
    });
  });

  it("un rejeu de refresh token prévient l'utilisateur (alerte de sécurité)", async () => {
    const s = await loginWithOtp(h, uniquePhone());
    await request(h.server)
      .post(`${API}/auth/refresh`)
      .send({ refreshToken: s.refreshToken })
      .expect(200);
    await request(h.server)
      .post(`${API}/auth/refresh`)
      .send({ refreshToken: s.refreshToken })
      .expect(401);
    await h.drainOutbox();
    const rows = await h.sql.query("SELECT type FROM ntf.notifications WHERE user_id = $1", [
      s.userId,
    ]);
    expect(rows.rows.map((r) => r.type)).toContain("SECURITY_SESSION_REVOKED");
  });

  describe("relais d'outbox", () => {
    it("un consommateur en échec est rejoué avec backoff puis part en file des morts", async () => {
      const relay = h.app.get(OutboxRelayService);
      const id = (
        await h.sql.query<{ id: string }>(
          `INSERT INTO ops.outbox_events (event_type, aggregate_type, aggregate_id, payload)
           VALUES ('BUSINESS_CREATED', 'business', gen_random_uuid(), '{"businessId":"not-a-uuid","ownerId":"x"}')
           RETURNING id`,
        )
      ).rows[0]!.id;
      await relay.drain();
      let row = (
        await h.sql.query(
          "SELECT attempts, last_error, failed_at, published_at FROM ops.outbox_events WHERE id = $1",
          [id],
        )
      ).rows[0];
      expect(row.attempts).toBe(1);
      expect(row.last_error).toEqual(expect.any(String));
      expect(row.published_at).toBeNull();

      await h.sql.query(
        "UPDATE ops.outbox_events SET attempts = 7, next_attempt_at = now() WHERE id = $1",
        [id],
      );
      await relay.drain();
      row = (
        await h.sql.query("SELECT attempts, failed_at FROM ops.outbox_events WHERE id = $1", [id])
      ).rows[0];
      expect(row.attempts).toBe(8);
      expect(row.failed_at).not.toBeNull();
      // Mis en file des morts = incident : remonté (Sentry en production), une seule fois.
      const reported = h.reportedErrors.filter((r) => r.context?.tags?.eventId === id);
      expect(reported).toHaveLength(1);
      expect(reported[0]!.context).toMatchObject({
        source: "outbox",
        tags: { eventType: "BUSINESS_CREATED" },
      });
      await h.sql.query("UPDATE ops.outbox_events SET next_attempt_at = now() WHERE id = $1", [id]);
      await relay.drain();
      expect(
        (await h.sql.query("SELECT attempts FROM ops.outbox_events WHERE id = $1", [id])).rows[0]
          .attempts,
      ).toBe(8); // plus jamais réclamé
    });
  });
});
