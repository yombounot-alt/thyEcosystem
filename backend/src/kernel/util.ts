import { badRequest } from "./errors.js";

// ─── Pagination par curseur opaque ───
export function encodeCursor(payload: unknown): string {
  return Buffer.from(JSON.stringify(payload)).toString("base64url");
}
// T n'est pas inféré (comme `meta<T>` dans kernel/auth/guards.ts) : chaque appel le précise selon
// la forme du curseur qu'il encode/décode (ex. decodeCursor<{ id: string }>(...)).
// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
export function decodeCursor<T>(cursor: string | undefined): T | null {
  if (!cursor) return null;
  try {
    return JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as T;
  } catch {
    throw badRequest("INVALID_CURSOR", "Curseur de pagination invalide");
  }
}
export function clampLimit(limit: number | undefined, def = 20, max = 50): number {
  const n = Math.floor(limit ?? def);
  return Number.isFinite(n) ? Math.min(max, Math.max(1, n)) : def;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

export const addDays = (d: Date, days: number) => new Date(d.getTime() + days * 86_400_000);
export const addMinutes = (d: Date, min: number) => new Date(d.getTime() + min * 60_000);
