import request from "supertest";
import { createHarness, type Harness } from "../harness.js";

describe("Contrat OpenAPI (e2e)", () => {
  describe("activé (défaut hors production)", () => {
    let h: Harness;
    beforeAll(async () => {
      h = await createHarness();
    });
    afterAll(async () => {
      await h.close();
    });

    it("est servi sans authentification, en JSON OpenAPI 3", async () => {
      const res = await request(h.server).get("/api/v1/openapi.json").expect(200);
      expect(res.headers["content-type"]).toMatch(/json/);
      expect(res.body.openapi).toMatch(/^3\./);
      expect(res.body.info.title).toBe("THY API");
      expect(res.body.servers).toEqual([{ url: "/api/v1" }]);
      expect(res.body.components.securitySchemes.bearer).toMatchObject({ scheme: "bearer" });
    });

    it("décrit les routes du kernel et des modules, relativement à /api/v1", async () => {
      const { body } = await request(h.server).get("/api/v1/openapi.json").expect(200);
      const paths = Object.keys(body.paths as Record<string, unknown>);
      for (const path of [
        "/auth/otp/request",
        "/me",
        "/businesses/{businessId}/invitations",
        "/me/invitations/{invitationId}/accept",
        "/me/notifications",
        "/businesses/{businessId}/subscription",
        "/products",
        "/sales",
        "/payments/{id}/verify",
      ])
        expect(paths, path).toContain(path);
      expect(paths.some((p) => p.startsWith("/api/v1"))).toBe(false);
    });
  });

  describe("désactivé (OPENAPI_ENABLED=false, défaut en production)", () => {
    let h: Harness;
    beforeAll(async () => {
      process.env.OPENAPI_ENABLED = "false";
      h = await createHarness();
    });
    afterAll(async () => {
      delete process.env.OPENAPI_ENABLED;
      await h.close();
    });

    it("n'est pas publié", async () => {
      await request(h.server).get("/api/v1/openapi.json").expect(404);
    });
  });
});
