import request from "supertest";
import {
  API,
  createBusiness,
  createHarness,
  loginWithOtp,
  uniquePhone,
  type Harness,
} from "../harness.js";

const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });

describe("/me et fiche d'entreprise — ce dont l'app a besoin pour démarrer (e2e)", () => {
  let h: Harness;
  beforeAll(async () => {
    h = await createHarness();
  });
  afterAll(async () => {
    await h.close();
  });

  it("un compte neuf n'a ni nom, ni entreprise, ni entreprise active", async () => {
    const phone = uniquePhone();
    const session = await loginWithOtp(h, phone);
    const me = await request(h.server)
      .get(`${API}/me`)
      .set(bearer(session.accessToken))
      .expect(200);
    expect(me.body).toMatchObject({
      phone,
      phoneVerified: true,
      fullName: null,
      activeBusinessId: null,
      businesses: [],
    });
  });

  it("le nom se renseigne après coup (PATCH /me) et /me le reflète", async () => {
    const session = await loginWithOtp(h, uniquePhone());
    const res = await request(h.server)
      .patch(`${API}/me`)
      .set(bearer(session.accessToken))
      .send({ fullName: "  Tamba Camara " })
      .expect(200);
    expect(res.body.fullName).toBe("Tamba Camara");
    await request(h.server)
      .patch(`${API}/me`)
      .set(bearer(session.accessToken))
      .send({ phone: "+224600000000" })
      .expect(400); // le numéro ne se change pas par ce chemin
  });

  it("après création : entreprise active, rôle OWNER et permissions effectives", async () => {
    const session = await loginWithOtp(h, uniquePhone());
    const business = await createBusiness(h, session, "Boutique /me");
    const me = await request(h.server)
      .get(`${API}/me`)
      .set(bearer(business.accessToken))
      .expect(200);
    expect(me.body.activeBusinessId).toBe(business.businessId);
    expect(me.body.businesses).toHaveLength(1);
    expect(me.body.businesses[0]).toMatchObject({
      id: business.businessId,
      name: "Boutique /me",
      currency: "GNF",
      roleCode: "OWNER",
    });
    expect(me.body.businesses[0].permissions).toEqual(
      expect.arrayContaining(["sales:create", "payments:verify", "members:manage"]),
    );

    // Avec l'ancien jeton (sans entreprise), le contexte n'est pas actif mais l'entreprise est listée.
    const stale = await request(h.server)
      .get(`${API}/me`)
      .set(bearer(session.accessToken))
      .expect(200);
    expect(stale.body.activeBusinessId).toBeNull();
    expect(stale.body.businesses).toHaveLength(1);
  });

  it("les permissions de /me suivent les surcharges accordées à un membre", async () => {
    const owner = await loginWithOtp(h, uniquePhone());
    const business = await createBusiness(h, owner, "Surcharges /me");
    const phone = uniquePhone();
    const invitation = await request(h.server)
      .post(`${API}/businesses/${business.businessId}/invitations`)
      .set(bearer(business.accessToken))
      .send({ phone, roleCode: "CASHIER" })
      .expect(201);
    const member = await loginWithOtp(h, phone);
    await request(h.server)
      .post(`${API}/invitations/accept`)
      .set(bearer(member.accessToken))
      .send({ token: invitation.body.token })
      .expect(200);
    await request(h.server)
      .put(`${API}/businesses/${business.businessId}/members/${member.userId}/permissions`)
      .set(bearer(business.accessToken))
      .send({ overrides: { "payments:verify": true } })
      .expect(200);

    const me = await request(h.server).get(`${API}/me`).set(bearer(member.accessToken)).expect(200);
    const row = me.body.businesses.find((b: { id: string }) => b.id === business.businessId);
    expect(row.roleCode).toBe("CASHIER");
    expect(row.permissions).toContain("payments:verify");
    expect(row.permissions).not.toContain("products:manage");
  });

  describe("GET /businesses/:id", () => {
    it("renvoie la fiche (adresse comprise) à tout membre, quel que soit son rôle", async () => {
      const owner = await loginWithOtp(h, uniquePhone());
      const created = await request(h.server)
        .post(`${API}/businesses`)
        .set(bearer(owner.accessToken))
        .send({
          name: "Chez Awa",
          businessType: "commerce",
          phone: "+224622000000",
          address: "Marché de Madina, Conakry",
        })
        .expect(201);
      expect(created.body.business.address).toBe("Marché de Madina, Conakry");
      const id = created.body.business.id as string;

      // Un VIEWER (le rôle le plus restreint) peut lire la fiche de son entreprise.
      const phone = uniquePhone();
      const invitation = await request(h.server)
        .post(`${API}/businesses/${id}/invitations`)
        .set(bearer(created.body.accessToken))
        .send({ phone, roleCode: "VIEWER" })
        .expect(201);
      const viewer = await loginWithOtp(h, phone);
      await request(h.server)
        .post(`${API}/invitations/accept`)
        .set(bearer(viewer.accessToken))
        .send({ token: invitation.body.token })
        .expect(200);

      for (const token of [created.body.accessToken, viewer.accessToken]) {
        const res = await request(h.server)
          .get(`${API}/businesses/${id}`)
          .set(bearer(token))
          .expect(200);
        expect(res.body).toMatchObject({
          id,
          name: "Chez Awa",
          currency: "GNF",
          phone: "+224622000000",
          address: "Marché de Madina, Conakry",
        });
      }
    });

    it("404 pour un non-membre (l'existence de l'entreprise n'est pas révélée)", async () => {
      const a = await createBusiness(h, await loginWithOtp(h, uniquePhone()), "Fiche A");
      const stranger = await loginWithOtp(h, uniquePhone());
      await request(h.server)
        .get(`${API}/businesses/${a.businessId}`)
        .set(bearer(stranger.accessToken))
        .expect(404);
    });

    it("401 sans jeton", async () => {
      await request(h.server).get(`${API}/businesses/${crypto.randomUUID()}`).expect(401);
    });
  });
});
