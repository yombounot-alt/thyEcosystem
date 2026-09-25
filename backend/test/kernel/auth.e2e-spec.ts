import request from "supertest";
import { API, createHarness, uniquePhone, type Harness } from "../harness.js";

describe("Auth — OTP, refresh, déconnexion (e2e)", () => {
  let h: Harness;

  beforeAll(async () => {
    h = await createHarness();
  });
  afterAll(async () => {
    await h.close();
  });

  const otpRequest = (phone: string) =>
    request(h.server).post(`${API}/auth/otp/request`).send({ phone });
  const otpVerify = (phone: string, code: string) =>
    request(h.server).post(`${API}/auth/otp/verify`).send({ phone, code });

  it("refuse un numéro qui n'est pas au format E.164", async () => {
    await otpRequest("0611111111").expect(400);
    await otpRequest("not-a-phone").expect(400);
  });

  it("inscription et connexion sont le même flux : OTP → session, puis /me", async () => {
    const phone = uniquePhone();
    await otpRequest(phone).expect((r) => {
      expect(r.status).toBeLessThan(300);
    });

    const bad = await otpVerify(phone, "000000");
    expect([400, 422]).toContain(bad.status);
    expect(bad.body.error.code).toBe("OTP_INVALID");

    const ok = await otpVerify(phone, h.otpFor(phone)).expect(200);
    expect(ok.body.accessToken).toBeDefined();
    expect(ok.body.refreshToken).toBeDefined();

    const me = await request(h.server)
      .get(`${API}/me`)
      .set("Authorization", `Bearer ${ok.body.accessToken}`)
      .expect(200);
    expect(me.body.phone).toBe(phone);

    // Même numéro, nouvelle session : c'est le même compte.
    await otpRequest(phone);
    const again = await otpVerify(phone, h.otpFor(phone)).expect(200);
    expect(again.body.user.id).toBe(ok.body.user.id);
  });

  it("un code OTP ne sert qu'une fois", async () => {
    const phone = uniquePhone();
    await otpRequest(phone);
    const code = h.otpFor(phone);
    await otpVerify(phone, code).expect(200);
    const replay = await otpVerify(phone, code);
    expect(replay.status).toBeGreaterThanOrEqual(400);
  });

  it("bloque un code après trop d'essais, même avec le bon code ensuite", async () => {
    const phone = uniquePhone();
    await otpRequest(phone);
    const good = h.otpFor(phone);
    const wrong = good === "111111" ? "222222" : "111111";
    for (let i = 0; i < 5; i++) await otpVerify(phone, wrong);
    const res = await otpVerify(phone, good);
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.body.error.code).toBe("OTP_TOO_MANY_ATTEMPTS");
  });

  it("limite le nombre de codes demandés pour un même numéro", async () => {
    const phone = uniquePhone();
    for (let i = 0; i < 3; i++)
      await otpRequest(phone).expect((r) => {
        expect(r.status).toBeLessThan(300);
      });
    const res = await otpRequest(phone);
    expect(res.status).toBe(429);
    expect(res.body.error.code).toBe("OTP_RATE_LIMITED");
  });

  it("refuse /me sans jeton ou avec un jeton falsifié", async () => {
    await request(h.server).get(`${API}/me`).expect(401);
    await request(h.server)
      .get(`${API}/me`)
      .set("Authorization", "Bearer eyJhbGciOiJIUzI1NiJ9.e30.forged")
      .expect(401);
  });

  it("fait tourner le refresh token et détecte le rejeu (toute la famille est révoquée)", async () => {
    const phone = uniquePhone();
    await otpRequest(phone);
    const session = (await otpVerify(phone, h.otpFor(phone)).expect(200)).body;

    const first = await request(h.server)
      .post(`${API}/auth/refresh`)
      .send({ refreshToken: session.refreshToken })
      .expect(200);
    expect(first.body.refreshToken).not.toBe(session.refreshToken);

    // Rejeu de l'ancien jeton : refusé…
    const replay = await request(h.server)
      .post(`${API}/auth/refresh`)
      .send({ refreshToken: session.refreshToken })
      .expect(401);
    expect(replay.body.error.code).toBe("AUTH_REFRESH_REUSED");

    // …et le jeton légitime issu de la rotation est révoqué avec sa famille.
    await request(h.server)
      .post(`${API}/auth/refresh`)
      .send({ refreshToken: first.body.refreshToken })
      .expect(401);
  });

  it("deux refresh simultanés avec le même jeton : un seul gagne", async () => {
    const phone = uniquePhone();
    await otpRequest(phone);
    const session = (await otpVerify(phone, h.otpFor(phone)).expect(200)).body;
    const results = await Promise.all(
      [1, 2, 3].map(() =>
        request(h.server).post(`${API}/auth/refresh`).send({ refreshToken: session.refreshToken }),
      ),
    );
    expect(results.filter((r) => r.status === 200)).toHaveLength(1);
  });

  it("révoque le refresh token à la déconnexion", async () => {
    const phone = uniquePhone();
    await otpRequest(phone);
    const session = (await otpVerify(phone, h.otpFor(phone)).expect(200)).body;
    await request(h.server)
      .post(`${API}/auth/logout`)
      .set("Authorization", `Bearer ${session.accessToken}`)
      .send({ refreshToken: session.refreshToken })
      .expect(204);
    await request(h.server)
      .post(`${API}/auth/refresh`)
      .send({ refreshToken: session.refreshToken })
      .expect(401);
  });

  it("ne stocke jamais un OTP ni un refresh token en clair", async () => {
    const phone = uniquePhone();
    await otpRequest(phone);
    const code = h.otpFor(phone);
    const session = (await otpVerify(phone, code).expect(200)).body;
    const otps = await h.sql.query("SELECT code_hash FROM core.otp_challenges WHERE phone = $1", [
      phone,
    ]);
    for (const row of otps.rows)
      expect(Buffer.from(row.code_hash).toString("utf8")).not.toContain(code);
    const rt = await h.sql.query(
      "SELECT count(*)::int AS n FROM core.refresh_tokens WHERE token_hash = convert_to($1, 'UTF8')",
      [session.refreshToken],
    );
    expect(rt.rows[0].n).toBe(0);
  });
});

describe("Auth — limitation de débit (e2e)", () => {
  let h: Harness;
  beforeAll(async () => {
    h = await createHarness({ rateLimit: true });
  });
  afterAll(async () => {
    await h.close();
    process.env.RATE_LIMIT_ENABLED = "false";
  });

  it("répond 429 avec Retry-After au-delà du plafond de vérifications OTP", async () => {
    const phone = uniquePhone();
    await request(h.server).post(`${API}/auth/otp/request`).send({ phone });
    let last = 0;
    let retryAfter: string | undefined;
    for (let i = 0; i < 12; i++) {
      const res = await request(h.server)
        .post(`${API}/auth/otp/verify`)
        .send({ phone, code: "000000" });
      last = res.status;
      retryAfter = res.headers["retry-after"];
      if (last === 429) break;
    }
    expect(last).toBe(429);
    expect(Number(retryAfter)).toBeGreaterThan(0);
  });
});
