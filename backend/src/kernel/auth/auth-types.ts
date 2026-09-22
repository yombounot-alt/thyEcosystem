import { SetMetadata } from "@nestjs/common";
import type { Request } from "express";

export interface AuthUser {
  id: string;
  status: "ACTIVE" | "SUSPENDED" | "BANNED" | "DELETED";
  phoneVerified: boolean;
  /** Entreprise active portée par le jeton d'accès courant (claim `bizId`), si l'utilisateur en a choisi une. */
  activeBusinessId: string | null;
}

/** Adhésion vérifiée en base pour la route `/businesses/:businessId/**` en cours (jamais déduite du seul JWT). */
export interface Membership {
  businessId: string;
  roleId: string;
  roleCode: string;
}

export type AuthedRequest = Request & { user: AuthUser; membership?: Membership; id?: string };

// ─── Métadonnées de route (refus par défaut : une route sans décorateur d'accès est rejetée) ───
export const PUBLIC_KEY = "thy:public";
export const AUTHENTICATED_KEY = "thy:authenticated";
export const REQUIRE_PERMISSION_KEY = "thy:require-permission";
export const REQUIRE_VERIFIED_PHONE_KEY = "thy:require-verified-phone";
export const ALLOW_RESTRICTED_KEY = "thy:allow-restricted";
export const RATE_LIMIT_KEY = "thy:rate-limit";

/** Route publique (aucune authentification). */
export const Public = () => SetMetadata(PUBLIC_KEY, true);
/** Route ouverte à tout utilisateur authentifié, sans notion d'entreprise (ex. GET /me). */
export const Authenticated = () => SetMetadata(AUTHENTICATED_KEY, true);
/**
 * Route sous `/businesses/:businessId/**` : exige d'être membre actif de CETTE entreprise
 * (vérifié en base à chaque requête, jamais depuis le seul JWT — voir docs/plans/consolidation-strategy.md §2)
 * ET de détenir la permission donnée. Non-membre ⇒ 404 (pas 403, pour ne pas révéler l'existence).
 */
export const RequirePermission = (code: string) => SetMetadata(REQUIRE_PERMISSION_KEY, code);
/** Exige un numéro de téléphone confirmé (actions sensibles : créer une entreprise, inviter…). */
export const RequireVerifiedPhone = () => SetMetadata(REQUIRE_VERIFIED_PHONE_KEY, true);
/** Autorise un compte suspendu à appeler cette route non-GET (ex. logout). */
export const AllowRestricted = () => SetMetadata(ALLOW_RESTRICTED_KEY, true);

export interface RateLimitOptions {
  name: string;
  limit: number;
  windowSec: number;
  /** ip : par IP · user : par utilisateur (repli IP) · ip+phone : par IP et téléphone du corps */
  by?: "ip" | "user" | "ip+phone";
  /** true : si Redis est indisponible, on REFUSE (OTP, création d'entreprise). Défaut : on laisse passer. */
  failClosed?: boolean;
}
export const RateLimit = (opts: RateLimitOptions) => SetMetadata(RATE_LIMIT_KEY, opts);
