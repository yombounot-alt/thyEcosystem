import { createParamDecorator, type ExecutionContext } from "@nestjs/common";
import type { AuthedRequest, AuthUser, Membership } from "./auth-types.js";

export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthUser => {
  return ctx.switchToHttp().getRequest<AuthedRequest>().user;
});

/** Adhésion (entreprise, rôle) vérifiée par le garde d'accès — disponible sur les routes `@RequirePermission`. */
export const CurrentMembership = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): Membership => {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    if (!req.membership)
      throw new Error("CurrentMembership utilisé sur une route sans @RequirePermission");
    return req.membership;
  },
);

/** Identifiant de l'entreprise de la requête (adhésion déjà vérifiée en base par AccessGuard). */
export const CurrentBusiness = createParamDecorator((_: unknown, ctx: ExecutionContext): string => {
  const req = ctx.switchToHttp().getRequest<AuthedRequest>();
  if (!req.membership)
    throw new Error("CurrentBusiness utilisé sur une route sans @RequirePermission");
  return req.membership.businessId;
});

/** Permissions effectives (rôle + surcharges) du membre courant, pour les contrôles fins dans un service. */
export const CurrentPermissions = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): string[] => {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    if (!req.permissions)
      throw new Error("CurrentPermissions utilisé sur une route sans @RequirePermission");
    return [...req.permissions];
  },
);

/** IP et appareil de la requête (pour l'anti-fraude). */
export interface ClientMeta {
  ip?: string;
  deviceId?: string;
  userAgent?: string;
}
export const Meta = createParamDecorator((_: unknown, ctx: ExecutionContext): ClientMeta => {
  const req = ctx.switchToHttp().getRequest<AuthedRequest>();
  const dev = req.headers["x-device-id"];
  const deviceId = typeof dev === "string" && /^[A-Za-z0-9-]{8,64}$/.test(dev) ? dev : undefined;
  return { ip: req.ip, deviceId, userAgent: String(req.headers["user-agent"] ?? "").slice(0, 200) };
});
