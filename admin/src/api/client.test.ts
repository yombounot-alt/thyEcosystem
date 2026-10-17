import { fakeApi } from "../test/fake-api";
import { api, ApiError, onUnauthorized, query, setCsrfToken } from "./client";

describe("client API admin", () => {
  afterEach(() => {
    setCsrfToken(null);
  });

  it("joint le jeton anti-CSRF aux écritures, jamais aux lectures", async () => {
    const { calls } = fakeApi({
      "GET /users": { body: [] },
      "POST /users/u1/suspend": { body: {} },
    });
    setCsrfToken("jeton");
    await api("GET", "/users");
    await api("POST", "/users/u1/suspend", { reason: "motif valable" });
    expect(calls[0]?.headers["X-CSRF-Token"]).toBeUndefined();
    expect(calls[1]?.headers["X-CSRF-Token"]).toBe("jeton");
    expect(calls[1]?.body).toEqual({ reason: "motif valable" });
  });

  it("transforme la réponse d'erreur de l'API en ApiError lisible", async () => {
    fakeApi({
      "GET /audit": {
        status: 403,
        body: { error: { code: "ADMIN_FORBIDDEN", message: "Droit manquant", requestId: "r-42" } },
      },
    });
    const error = await api("GET", "/audit").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 403, code: "ADMIN_FORBIDDEN", requestId: "r-42" });
  });

  it("signale une session expirée hors des routes d'authentification", async () => {
    fakeApi({
      "GET /users": {
        status: 401,
        body: { error: { code: "STAFF_SESSION_EXPIRED", message: "Session expirée" } },
      },
      "POST /auth/login": {
        status: 401,
        body: { error: { code: "STAFF_INVALID_CREDENTIALS", message: "Identifiants invalides" } },
      },
    });
    const listener = vi.fn();
    const off = onUnauthorized(listener);
    await api("POST", "/auth/login", {}).catch(() => undefined);
    expect(listener).not.toHaveBeenCalled();
    await api("GET", "/users").catch(() => undefined);
    expect(listener).toHaveBeenCalledOnce();
    off();
  });

  it("donne un message clair quand le serveur est injoignable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.reject(new TypeError("Failed to fetch"))),
    );
    await expect(api("GET", "/users")).rejects.toMatchObject({ code: "NETWORK", status: 0 });
  });

  it("construit la chaîne de requête sans les valeurs vides", () => {
    expect(query({ q: "+224 62", cursor: undefined, limit: 20, actorType: "" })).toBe(
      "?q=%2B224+62&limit=20",
    );
    expect(query({ q: "" })).toBe("");
  });
});
