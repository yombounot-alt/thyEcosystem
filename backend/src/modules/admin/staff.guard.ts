import {
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  Injectable,
  SetMetadata,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Request } from "express";
import { forbidden, unauthorized } from "../../kernel/errors.js";
import { safeEqual, sha256 } from "../../kernel/security/crypto.service.js";
import { StaffAuthService, type StaffPrincipal } from "./staff-auth.service.js";

export const STAFF_SESSION_COOKIE = "thy_admin_session";
export const CSRF_HEADER = "x-csrf-token";

const ADMIN_PERMISSION_KEY = "thy:admin-permission";
const MFA_PENDING_ALLOWED_KEY = "thy:admin-mfa-pending";

/** Permission plateforme exigée par la route (`admin:users.read`…). */
export const AdminPermission = (code: string) => SetMetadata(ADMIN_PERMISSION_KEY, code);
/** Route accessible pendant la double authentification (enrôlement, saisie du code). */
export const AllowMfaPending = () => SetMetadata(MFA_PENDING_ALLOWED_KEY, true);

export type StaffRequest = Request & { staff?: StaffPrincipal };

/** Lit un cookie de l'en-tête (pas de dépendance `cookie-parser` pour un seul cookie). */
export function readCookie(req: Request, name: string): string | undefined {
  const header = req.headers.cookie;
  if (!header) return undefined;
  for (const part of header.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return decodeURIComponent(rest.join("="));
  }
  return undefined;
}

/**
 * Garde de la console d'administration — REFUS PAR DÉFAUT :
 *   1. session staff valide (cookie HttpOnly) ;
 *   2. double authentification faite (sauf routes d'enrôlement explicitement marquées) ;
 *   3. jeton anti-CSRF (en-tête X-CSRF-Token) sur toute requête qui modifie ;
 *   4. permission plateforme de la route, si elle en déclare une.
 * Les comptes clients n'y ont jamais accès : ce garde ne connaît que les sessions staff.
 */
@Injectable()
export class StaffGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly auth: StaffAuthService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<StaffRequest>();
    const token = readCookie(req, STAFF_SESSION_COOKIE);
    if (!token) throw unauthorized("STAFF_UNAUTHENTICATED", "Connexion staff requise");
    const principal = await this.auth.authenticate(token);
    if (!principal)
      throw unauthorized("STAFF_SESSION_EXPIRED", "Session expirée, reconnectez-vous");

    const targets = [ctx.getHandler(), ctx.getClass()];
    const pendingAllowed = this.reflector.getAllAndOverride<boolean>(
      MFA_PENDING_ALLOWED_KEY,
      targets,
    );
    if (!principal.mfaVerified && !pendingAllowed)
      throw unauthorized("STAFF_MFA_REQUIRED", "Double authentification requise");

    if (!["GET", "HEAD", "OPTIONS"].includes(req.method)) {
      const header = req.headers[CSRF_HEADER];
      if (typeof header !== "string" || !safeEqual(sha256(header), principal.csrfHash))
        throw forbidden("CSRF_INVALID", "Jeton anti-CSRF manquant ou invalide");
    }

    const permission = this.reflector.getAllAndOverride<string>(ADMIN_PERMISSION_KEY, targets);
    if (permission && !principal.permissions.has(permission))
      throw forbidden("ADMIN_FORBIDDEN", "Action non autorisée pour votre rôle");

    req.staff = principal;
    return true;
  }
}

export const CurrentStaff = createParamDecorator((_: unknown, ctx: ExecutionContext) => {
  const staff = ctx.switchToHttp().getRequest<StaffRequest>().staff;
  if (!staff) throw new Error("CurrentStaff utilisé sans StaffGuard");
  return staff;
});
