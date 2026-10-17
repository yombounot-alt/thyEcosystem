import { vi } from "vitest";

export interface Call {
  method: string;
  path: string;
  body: unknown;
  headers: Record<string, string>;
}

type Reply =
  { status?: number; body?: unknown } | ((call: Call) => { status?: number; body?: unknown });

/**
 * Faux serveur pour les tests : `routes` associe "MÉTHODE /chemin" (sans /admin/v1) à une réponse.
 * Toute requête non prévue échoue bruyamment (404 + trace) pour ne rien laisser passer en silence.
 */
export function fakeApi(routes: Record<string, Reply>) {
  const calls: Call[] = [];
  const fetchMock = vi.fn((input: string, init?: RequestInit) => {
    const url = new URL(input, "http://localhost");
    const path = url.pathname.replace(/^\/admin\/v1/, "") + url.search;
    const call: Call = {
      method: init?.method ?? "GET",
      path,
      body: typeof init?.body === "string" ? JSON.parse(init.body) : undefined,
      headers: (init?.headers ?? {}) as Record<string, string>,
    };
    calls.push(call);
    const key = `${call.method} ${url.pathname.replace(/^\/admin\/v1/, "")}`;
    const route = routes[key];
    const reply = typeof route === "function" ? route(call) : route;
    if (!reply) {
      return Promise.resolve(
        new Response(JSON.stringify({ error: { code: "TEST_UNROUTED", message: key } }), {
          status: 404,
        }),
      );
    }
    const status = reply.status ?? 200;
    return Promise.resolve(
      new Response(status === 204 ? null : JSON.stringify(reply.body ?? {}), { status }),
    );
  });
  vi.stubGlobal("fetch", fetchMock);
  return { calls };
}

export function session(permissions: string[], overrides: Record<string, unknown> = {}) {
  return {
    staff: {
      id: "s1",
      email: "awa@thy.test",
      fullName: "Awa Camara",
      roles: ["SUPPORT_AGENT"],
      permissions,
    },
    mfaVerified: true,
    mfaEnrollmentRequired: false,
    csrfToken: "csrf-1",
    ...overrides,
  };
}

export const unauthenticated = {
  status: 401,
  body: { error: { code: "STAFF_UNAUTHENTICATED", message: "Connexion requise" } },
};
