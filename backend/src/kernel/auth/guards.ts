import { CanActivate, ExecutionContext, Inject, Injectable } from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Response } from "express";
import { CONFIG, type AppConfig } from "../config/config.js";
import { AppError, forbidden, notFound, unauthorized } from "../errors.js";
import { RedisService } from "../redis/redis.service.js";
import { sha256 } from "../security/crypto.service.js";
import {
  ALLOW_RESTRICTED_KEY,
  AUTHENTICATED_KEY,
  PUBLIC_KEY,
  RATE_LIMIT_KEY,
  REQUIRE_MEMBERSHIP_KEY,
  REQUIRE_PERMISSION_KEY,
  REQUIRE_VERIFIED_PHONE_KEY,
  type AuthedRequest,
  type RateLimitOptions,
} from "./auth-types.js";
import { PermissionsService } from "./permissions.service.js";
import { TokenService } from "./token.service.js";
import { UserStateService } from "./user-state.service.js";

/**
 * T n'est pas inféré depuis un argument (comme `Reflector#getAllAndOverride` lui-même) : chaque
 * appel le précise explicitement (`meta<boolean>(...)`), ce qui est le but recherché, pas un oubli.
 */
// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
function meta<T>(reflector: Reflector, key: string, ctx: ExecutionContext): T | undefined {
  return reflector.getAllAndOverride<T>(key, [ctx.getHandler(), ctx.getClass()]);
}

/** 1. Authentification : JWT valide + compte non banni/supprimé + version de jeton à jour. */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly tokens: TokenService,
    private readonly states: UserStateService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    if (meta<boolean>(this.reflector, PUBLIC_KEY, ctx)) return true;
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const header = req.headers.authorization;
    if (!header?.startsWith("Bearer ")) throw unauthorized();
    const claims = await this.tokens.verifyAccess(header.slice(7));
    if (!claims) throw unauthorized("AUTH_INVALID_TOKEN", "Session expirée ou invalide");

    const state = await this.states.get(claims.sub);
    if (state?.tokenVersion !== claims.ver)
      throw unauthorized("AUTH_INVALID_TOKEN", "Session expirée ou invalide");
    if (state.status === "BANNED" || state.status === "DELETED")
      throw forbidden("ACCOUNT_DISABLED", "Compte désactivé");

    req.user = {
      id: state.id,
      status: state.status,
      phoneVerified: state.phoneVerified,
      activeBusinessId: claims.bizId,
    };
    return true;
  }
}

/** 2. Limitation de débit (Redis). Défaut : 120 requêtes/min par utilisateur (repli IP). */
@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly redis: RedisService,
    @Inject(CONFIG) private readonly cfg: AppConfig,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    if (!this.cfg.rateLimitEnabled) return true;
    const opts: RateLimitOptions = meta<RateLimitOptions>(this.reflector, RATE_LIMIT_KEY, ctx) ?? {
      name: "default",
      limit: 120,
      windowSec: 60,
      by: "user",
    };
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const res = ctx.switchToHttp().getResponse<Response>();
    const ip = req.ip ?? "unknown";
    let subject: string;
    switch (opts.by ?? "user") {
      case "ip":
        subject = ip;
        break;
      case "ip+phone": {
        const body = req.body as { phone?: unknown } | undefined;
        const phone = typeof body?.phone === "string" ? body.phone : "";
        subject = `${ip}:${sha256(phone).toString("hex").slice(0, 16)}`;
        break;
      }
      default:
        subject = req.user?.id ?? ip;
    }
    try {
      const { count, ttl } = await this.redis.incrWindow(
        `rl:${opts.name}:${subject}`,
        opts.windowSec,
      );
      res.setHeader("RateLimit-Limit", opts.limit);
      res.setHeader("RateLimit-Remaining", Math.max(0, opts.limit - count));
      res.setHeader("RateLimit-Reset", ttl);
      if (count > opts.limit) {
        res.setHeader("Retry-After", ttl);
        throw new AppError("RATE_LIMITED", 429, "Trop de requêtes, réessayez plus tard", {
          retryAfterSec: ttl,
        });
      }
      return true;
    } catch (e) {
      if (e instanceof AppError) throw e;
      if (opts.failClosed)
        throw new AppError("SERVICE_UNAVAILABLE", 503, "Service temporairement indisponible");
      return true; // Redis indisponible : on préfère servir (lecture) que tout bloquer
    }
  }
}

/**
 * 3. Accès : REFUS PAR DÉFAUT (une route sans @Public/@Authenticated/@RequirePermission est rejetée).
 * Pour @RequirePermission : relit l'adhésion en base à CHAQUE requête (jamais le claim `bizId` du
 * JWT, qui n'est qu'un confort d'UX) ; non-membre ⇒ 404 (n'expose pas l'existence de la ressource).
 */
@Injectable()
export class AccessGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly permissions: PermissionsService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    if (meta<boolean>(this.reflector, PUBLIC_KEY, ctx)) return true;
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const user = req.user;
    // Route non publique (le PUBLIC_KEY ci-dessus l'aurait court-circuitée) : AuthGuard, qui
    // tourne avant (voir kernel.module.ts), a nécessairement déjà posé req.user.
    if (!user) throw unauthorized();

    const authenticated = meta<boolean>(this.reflector, AUTHENTICATED_KEY, ctx);
    const requiredPermission = meta<string>(this.reflector, REQUIRE_PERMISSION_KEY, ctx);
    const requireMembership = meta<boolean>(this.reflector, REQUIRE_MEMBERSHIP_KEY, ctx);
    if (!authenticated && !requiredPermission && !requireMembership)
      throw forbidden("ROUTE_NOT_ANNOTATED", "Accès non défini pour cette route");

    // État du compte : un compte SUSPENDED reste en lecture seule (docs/blueprint/04-identity-access.md §6).
    const mutating = !["GET", "HEAD", "OPTIONS"].includes(req.method);
    if (
      user.status === "SUSPENDED" &&
      mutating &&
      !meta<boolean>(this.reflector, ALLOW_RESTRICTED_KEY, ctx)
    ) {
      throw forbidden("ACCOUNT_RESTRICTED", "Votre compte est en lecture seule");
    }
    if (meta<boolean>(this.reflector, REQUIRE_VERIFIED_PHONE_KEY, ctx) && !user.phoneVerified) {
      throw forbidden("PHONE_NOT_VERIFIED", "Confirmez votre numéro de téléphone pour continuer");
    }

    // @Authenticated() seul : aucune entreprise à vérifier
    if (!requiredPermission && !requireMembership) return true;

    // Entreprise visée : le paramètre de route s'il existe, sinon le claim du jeton (routes « à plat »).
    const routeBusinessId = req.params.businessId;
    const fromRoute = typeof routeBusinessId === "string" && routeBusinessId.length > 0;
    const businessId = fromRoute ? routeBusinessId : user.activeBusinessId;
    if (!businessId)
      throw forbidden(
        "NO_ACTIVE_BUSINESS",
        "Aucune entreprise active : sélectionnez une entreprise.",
      );

    const membership = await this.permissions.getMembership(user.id, businessId);
    if (!membership) {
      // Paramètre de route : 404, jamais 403 (n'expose pas l'existence de l'entreprise).
      // Claim du jeton : l'utilisateur a été retiré de l'entreprise depuis l'émission du jeton.
      if (fromRoute) throw notFound();
      throw forbidden("NOT_A_MEMBER", "Vous n'êtes plus membre de cette entreprise.");
    }
    const effective = await this.permissions.getEffectivePermissions(membership);
    if (requiredPermission && !effective.has(requiredPermission))
      throw forbidden("FORBIDDEN_PERMISSION", "Action non autorisée pour votre rôle");

    req.membership = membership;
    req.permissions = effective;
    return true;
  }
}
