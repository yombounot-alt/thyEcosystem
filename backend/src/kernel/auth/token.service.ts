import { Inject, Injectable } from "@nestjs/common";
import { SignJWT, jwtVerify } from "jose";
import { CONFIG, type AppConfig } from "../config/config.js";

export interface AccessClaims {
  sub: string;
  ver: number;
  /** Entreprise active, si l'utilisateur en a choisi une (voir POST /me/active-business). */
  bizId: string | null;
}

@Injectable()
export class TokenService {
  private readonly key: Uint8Array;

  constructor(@Inject(CONFIG) private readonly cfg: AppConfig) {
    this.key = new TextEncoder().encode(cfg.jwt.secret);
  }

  /**
   * JWT d'accès court (15 min par défaut). `ver` = users.token_version (révocation globale
   * immédiate à la prochaine vérification). `bizId` est un confort d'UX (contexte par défaut),
   * JAMAIS la source d'autorité : `/businesses/:id/**` revérifie toujours l'adhésion en base
   * (voir docs/plans/consolidation-strategy.md §2).
   */
  async signAccess(
    userId: string,
    tokenVersion: number,
    businessId: string | null = null,
  ): Promise<string> {
    return new SignJWT({ ver: tokenVersion, bizId: businessId })
      .setProtectedHeader({ alg: "HS256" })
      .setSubject(userId)
      .setIssuer(this.cfg.jwt.issuer)
      .setIssuedAt()
      .setExpirationTime(`${this.cfg.jwt.accessTtlSec}s`)
      .sign(this.key);
  }

  /** Retourne les claims si la signature, l'émetteur et l'expiration sont valides, sinon null. */
  async verifyAccess(token: string): Promise<AccessClaims | null> {
    try {
      const { payload } = await jwtVerify(token, this.key, {
        issuer: this.cfg.jwt.issuer,
        algorithms: ["HS256"],
      });
      if (typeof payload.sub !== "string" || typeof payload.ver !== "number") return null;
      const bizId = typeof payload.bizId === "string" ? payload.bizId : null;
      return { sub: payload.sub, ver: payload.ver, bizId };
    } catch {
      return null;
    }
  }
}
