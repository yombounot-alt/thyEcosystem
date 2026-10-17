/**
 * Client HTTP de l'admin. La session vit dans un cookie HttpOnly posé par l'API (jamais lisible
 * ici) ; le jeton anti-CSRF, lui, est gardé en mémoire uniquement et joint à chaque requête qui
 * modifie quelque chose. Il est renouvelé à chaque lecture de /auth/session.
 */
export const ADMIN_API = "/admin/v1";

let csrfToken: string | null = null;

export function setCsrfToken(token: string | null): void {
  csrfToken = token;
}

/** Erreur renvoyée par l'API : { error: { code, message, details?, requestId } }. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly requestId?: string,
  ) {
    super(message);
    this.name = "ApiError";
  }

  /** La session a disparu ou expiré : il faut se reconnecter. */
  get needsLogin(): boolean {
    return this.status === 401 && this.code !== "STAFF_MFA_REQUIRED";
  }
}

type Method = "GET" | "POST" | "PUT" | "DELETE";

interface ErrorBody {
  error?: { code?: string; message?: string; requestId?: string };
}

const unauthorizedListeners = new Set<() => void>();

/** Appelé quand une requête révèle que la session n'est plus valable. */
export function onUnauthorized(listener: () => void): () => void {
  unauthorizedListeners.add(listener);
  return () => unauthorizedListeners.delete(listener);
}

export async function api<T>(method: Method, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (method !== "GET" && csrfToken) headers["X-CSRF-Token"] = csrfToken;

  let res: Response;
  try {
    res = await fetch(`${ADMIN_API}${path}`, {
      method,
      headers,
      credentials: "same-origin",
      body: body === undefined ? null : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, "NETWORK", "Impossible de joindre le serveur. Vérifiez la connexion.");
  }

  if (res.status === 204) return undefined as T;
  const data = (await res.json().catch(() => null)) as unknown;
  if (!res.ok) {
    const err = (data as ErrorBody | null)?.error;
    const error = new ApiError(
      res.status,
      err?.code ?? `HTTP_${String(res.status)}`,
      err?.message ?? messageForStatus(res.status),
      err?.requestId,
    );
    if (error.needsLogin && !path.startsWith("/auth/")) {
      for (const listener of unauthorizedListeners) listener();
    }
    throw error;
  }
  return data as T;
}

function messageForStatus(status: number): string {
  if (status === 403) return "Vous n'avez pas les droits nécessaires pour cette action.";
  if (status === 404) return "Élément introuvable.";
  if (status === 429) return "Trop de tentatives. Patientez quelques minutes.";
  if (status >= 500) return "Erreur du serveur. Réessayez dans un instant.";
  return "La requête a échoué.";
}

/** Construit une chaîne de requête en ignorant les valeurs vides. */
export function query(params: Record<string, string | number | undefined | null>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") search.set(key, String(value));
  }
  const text = search.toString();
  return text ? `?${text}` : "";
}
