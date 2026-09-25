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
  /** Écarts individuels par rapport aux permissions du rôle (voir PermissionsService). */
  permissionOverrides: Record<string, boolean> | null;
}

export type AuthedRequest = Request & {
  // Non défini pour les routes @Public() : AuthGuard s'arrête avant de le poser (guards.ts).
  // Ne jamais retirer le `?` pour « simplifier » — RateLimitGuard tourne aussi sur ces routes.
  user?: AuthUser;
  membership?: Membership;
  /** Permissions effectives (rôle + surcharges) du membre pour l'entreprise de la requête. */
  permissions?: Set<string>;
  id?: string;
};

// ─── Métadonnées de route (refus par défaut : une route sans décorateur d'accès est rejetée) ───
export const PUBLIC_KEY = "thy:public";
export const AUTHENTICATED_KEY = "thy:authenticated";
export const REQUIRE_PERMISSION_KEY = "thy:require-permission";
export const REQUIRE_MEMBERSHIP_KEY = "thy:require-membership";
export const REQUIRE_VERIFIED_PHONE_KEY = "thy:require-verified-phone";
export const ALLOW_RESTRICTED_KEY = "thy:allow-restricted";
export const RATE_LIMIT_KEY = "thy:rate-limit";

/** Route publique (aucune authentification). */
export const Public = () => SetMetadata(PUBLIC_KEY, true);
/** Route ouverte à tout utilisateur authentifié, sans notion d'entreprise (ex. GET /me). */
export const Authenticated = () => SetMetadata(AUTHENTICATED_KEY, true);
/**
 * Route liée à une entreprise : exige d'être membre actif de CETTE entreprise ET de détenir la
 * permission donnée. L'entreprise est celle du paramètre `:businessId` si la route en a un
 * (non-membre ⇒ 404, pas 403, pour ne pas révéler l'existence) ; sinon celle du claim `bizId` du
 * jeton (routes « à plat » de THY Business, ex. `/products`) — dans les deux cas l'adhésion et les
 * permissions sont RELUES EN BASE à chaque requête : le claim ne fait que désigner l'entreprise,
 * il n'accorde rien (voir docs/plans/consolidation-strategy.md §2).
 */
export const RequirePermission = (code: string) => SetMetadata(REQUIRE_PERMISSION_KEY, code);
/**
 * Comme @RequirePermission, sans permission précise : il suffit d'être membre actif de l'entreprise
 * visée (ex. lire la fiche de SA propre entreprise). Même résolution de l'entreprise, même 404
 * pour un non-membre.
 */
export const RequireMembership = () => SetMetadata(REQUIRE_MEMBERSHIP_KEY, true);
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
