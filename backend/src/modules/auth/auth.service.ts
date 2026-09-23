import { Inject, Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import type { ClientMeta } from "../../kernel/auth/current-user.js";
import { PermissionsService } from "../../kernel/auth/permissions.service.js";
import { TokenService } from "../../kernel/auth/token.service.js";
import { UserStateService } from "../../kernel/auth/user-state.service.js";
import { CONFIG, type AppConfig } from "../../kernel/config/config.js";
import { Db } from "../../kernel/db/db.service.js";
import { forbidden, notFound, unauthorized } from "../../kernel/errors.js";
import { OutboxService } from "../../kernel/infra.services.js";
import { CryptoService } from "../../kernel/security/crypto.service.js";
import { addDays } from "../../kernel/util.js";
import { OtpService } from "./otp.service.js";

interface UserRow {
  id: string;
  phone: string;
  email: string | null;
  fullName: string | null;
  status: "ACTIVE" | "SUSPENDED" | "BANNED" | "DELETED";
  tokenVersion: number;
  phoneVerifiedAt: Date | null;
  locale: string;
  timezone: string;
}

export interface Session {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  user: ReturnType<typeof publicUser>;
}

export const publicUser = (u: UserRow) => ({
  id: u.id,
  phone: u.phone,
  email: u.email,
  fullName: u.fullName,
  locale: u.locale,
  timezone: u.timezone,
  phoneVerified: u.phoneVerifiedAt !== null,
});

const USER_COLUMNS = `id, phone, email, full_name, status, token_version, phone_verified_at, locale, timezone`;

@Injectable()
export class AuthService {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    private readonly tokens: TokenService,
    private readonly otp: OtpService,
    private readonly states: UserStateService,
    private readonly permissions: PermissionsService,
    private readonly outbox: OutboxService,
    @Inject(CONFIG) private readonly cfg: AppConfig,
  ) {}

  async otpRequest(phone: string): Promise<void> {
    await this.otp.request(phone);
  }

  /**
   * Inscription ET connexion sont le même flux : le compte est créé au premier code vérifié pour
   * ce numéro (docs/blueprint/04-identity-access.md §2.2). `ON CONFLICT` rend l'opération atomique
   * et idempotente — pas de risque de doublon même sous requêtes concurrentes.
   */
  async otpVerify(phone: string, code: string, meta: ClientMeta): Promise<Session> {
    await this.otp.verify(phone, code);
    const user = await this.db.one<UserRow>(
      `INSERT INTO core.users (phone, phone_verified_at) VALUES ($1, now())
         ON CONFLICT (phone) WHERE status <> 'DELETED'
         DO UPDATE SET phone_verified_at = COALESCE(core.users.phone_verified_at, now())
       RETURNING ${USER_COLUMNS}`,
      [phone],
    );
    if (!user) throw new Error("otpVerify: upsert utilisateur sans résultat");
    if (user.status === "BANNED" || user.status === "DELETED")
      throw forbidden("ACCOUNT_DISABLED", "Compte désactivé");
    await this.db.query("UPDATE core.users SET last_login_at = now() WHERE id = $1", [user.id]);
    return this.issueSession(user, meta, randomUUID());
  }

  async refresh(refreshToken: string, meta: ClientMeta, businessId?: string): Promise<Session> {
    const hash = this.crypto.tokenHash(refreshToken);
    const row = await this.db.one<{
      id: string;
      userId: string;
      familyId: string;
      expiresAt: Date;
      revokedAt: Date | null;
    }>(
      "SELECT id, user_id, family_id, expires_at, revoked_at FROM core.refresh_tokens WHERE token_hash = $1",
      [hash],
    );
    if (!row) throw unauthorized("AUTH_REFRESH_INVALID", "Session invalide");
    if (row.revokedAt) {
      // Jeton déjà consommé : rejeu ⇒ vol probable. On révoque toute la famille.
      await this.db.tx(async (tx) => {
        const killed = await tx.query(
          "UPDATE core.refresh_tokens SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL",
          [row.familyId],
        );
        if (killed.rowCount > 0)
          await this.outbox.emit(tx, "SECURITY_TOKEN_REUSE", "user", row.userId, {
            userId: row.userId,
            familyId: row.familyId,
          });
      });
      throw unauthorized("AUTH_REFRESH_REUSED", "Session invalide, reconnectez-vous");
    }
    if (row.expiresAt < new Date()) throw unauthorized("AUTH_REFRESH_INVALID", "Session expirée");

    // Consommation atomique : si deux requêtes concurrentes présentent le même jeton, une seule gagne.
    const consumed = await this.db.query(
      "UPDATE core.refresh_tokens SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL",
      [row.id],
    );
    if (consumed.rowCount === 0)
      throw unauthorized("AUTH_REFRESH_REUSED", "Session invalide, reconnectez-vous");

    const user = await this.db.one<UserRow>(
      `SELECT ${USER_COLUMNS} FROM core.users WHERE id = $1`,
      [row.userId],
    );
    if (!user || user.status === "BANNED" || user.status === "DELETED")
      throw forbidden("ACCOUNT_DISABLED", "Compte désactivé");
    return this.issueSession(user, meta, row.familyId, row.id, businessId);
  }

  async logout(refreshToken: string, userId: string): Promise<void> {
    await this.db.query(
      `UPDATE core.refresh_tokens SET revoked_at = COALESCE(revoked_at, now())
        WHERE user_id = $2 AND family_id = (SELECT family_id FROM core.refresh_tokens WHERE token_hash = $1 AND user_id = $2)`,
      [this.crypto.tokenHash(refreshToken), userId],
    );
  }

  /**
   * Réémet un jeton d'accès avec l'entreprise active portée en claim `bizId` — utilisé après la
   * création d'une entreprise et par `POST /businesses/:id/activate` (changement de contexte).
   * L'adhésion est vérifiée à cet instant ; le claim n'est ensuite qu'un confort d'UX, jamais
   * la source d'autorité pour les routes `/businesses/:id/**` (voir kernel/auth/guards.ts).
   */
  async reissueWithBusiness(
    userId: string,
    businessId: string,
  ): Promise<{ accessToken: string; expiresIn: number; role: string; permissions: string[] }> {
    const membership = await this.permissions.getMembership(userId, businessId);
    if (!membership) throw notFound();
    const state = await this.states.get(userId);
    if (!state) throw unauthorized();
    const accessToken = await this.tokens.signAccess(userId, state.tokenVersion, businessId);
    // Rôle et permissions effectives : l'app s'en sert pour masquer ce que l'utilisateur ne peut
    // pas faire (l'autorité reste le serveur, qui les relit à chaque requête).
    const permissions = [...(await this.permissions.getEffectivePermissions(membership))].sort();
    return {
      accessToken,
      expiresIn: this.cfg.jwt.accessTtlSec,
      role: membership.roleCode,
      permissions,
    };
  }

  private async issueSession(
    user: UserRow,
    meta: ClientMeta,
    familyId: string,
    replacedId?: string,
    businessId?: string,
  ): Promise<Session> {
    const refreshToken = this.crypto.randomToken();
    const ipHash = this.crypto.ipHash(meta.ip);
    await this.db.tx(async (tx) => {
      const inserted = await tx.query<{ id: string }>(
        `INSERT INTO core.refresh_tokens (user_id, family_id, token_hash, ip_hash, user_agent, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
        [
          user.id,
          familyId,
          this.crypto.tokenHash(refreshToken),
          ipHash,
          meta.userAgent ?? null,
          addDays(new Date(), this.cfg.jwt.refreshTtlDays),
        ],
      );
      if (replacedId)
        await tx.query("UPDATE core.refresh_tokens SET replaced_by = $2 WHERE id = $1", [
          replacedId,
          inserted.rows[0]!.id,
        ]);
      await tx.query(
        "INSERT INTO core.login_events (user_id, ip_hash, success) VALUES ($1, $2, true)",
        [user.id, ipHash],
      );
    });
    // Entreprise active conservée au renouvellement, seulement si l'utilisateur en est toujours
    // membre (sinon le claim est omis et le client en sélectionne une).
    const activeBusinessId =
      businessId && (await this.permissions.getMembership(user.id, businessId)) ? businessId : null;
    const accessToken = await this.tokens.signAccess(user.id, user.tokenVersion, activeBusinessId);
    return {
      accessToken,
      refreshToken,
      expiresIn: this.cfg.jwt.accessTtlSec,
      user: publicUser(user),
    };
  }
}
