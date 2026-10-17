import { Injectable } from "@nestjs/common";
import { UserStateService } from "../../kernel/auth/user-state.service.js";
import { conflict, notFound } from "../../kernel/errors.js";
import { maskPhone } from "../../kernel/notifications/console-sms-sender.adapter.js";
import { clampLimit, decodeCursor, encodeCursor, type Page } from "../../kernel/util.js";
import { AdminDb, auditStaff } from "./admin-db.service.js";
import type { StaffPrincipal } from "./staff-auth.service.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface UserListItem {
  id: string;
  fullName: string | null;
  /** Masqué par défaut : l'afficher en clair est une action auditée (revealPhone). */
  phoneMasked: string;
  status: string;
  createdAt: Date;
  lastLoginAt: Date | null;
}

/**
 * Utilisateurs vus par le support (docs/blueprint/09-admin.md §2, §4 « Users ») : lecture avec
 * numéros masqués ; révélation, suspension et révocation de sessions = actions motivées et auditées.
 * Pas d'usurpation de session, pas de modification du profil.
 */
@Injectable()
export class AdminUsersService {
  constructor(
    private readonly db: AdminDb,
    private readonly states: UserStateService,
  ) {}

  async search(
    q: string | undefined,
    limit?: number,
    cursor?: string,
  ): Promise<Page<UserListItem>> {
    const n = clampLimit(limit, 20, 50);
    const after = decodeCursor<{ c: string; i: string }>(cursor);
    const params: unknown[] = [];
    const where: string[] = ["status <> 'DELETED'"];
    const term = q?.trim() ?? "";
    if (UUID.test(term)) {
      params.push(term);
      where.push(`id = $${params.length}`);
    } else if (/^\+?[\d\s]{3,}$/.test(term)) {
      // Numéro (ou début de numéro) : les espaces saisis sont ignorés.
      params.push(`${term.replace(/\s/g, "").replace(/^(?!\+)/, "+")}%`);
      where.push(`phone LIKE $${params.length}`);
    } else if (term.length > 0) {
      params.push(`%${term}%`);
      where.push(`full_name ILIKE $${params.length}`);
    }
    if (after) {
      params.push(after.c, after.i);
      where.push(
        `(created_at, id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`,
      );
    }
    params.push(n + 1);
    const rows = await this.db.query<{
      id: string;
      fullName: string | null;
      phone: string;
      status: string;
      createdAt: Date;
      lastLoginAt: Date | null;
    }>(
      `SELECT id, full_name, phone, status, created_at, last_login_at FROM core.users
        WHERE ${where.join(" AND ")}
        ORDER BY created_at DESC, id DESC LIMIT $${params.length}`,
      params,
    );
    const items = rows.rows.slice(0, n).map(({ phone, ...u }) => ({
      ...u,
      phoneMasked: maskPhone(phone),
    }));
    const last = items.at(-1);
    return {
      items,
      nextCursor:
        rows.rows.length > n && last
          ? encodeCursor({ c: new Date(last.createdAt).toISOString(), i: last.id })
          : null,
    };
  }

  async detail(id: string) {
    const user = await this.db.one<{
      id: string;
      fullName: string | null;
      phone: string;
      status: string;
      locale: string;
      phoneVerifiedAt: Date | null;
      createdAt: Date;
      lastLoginAt: Date | null;
    }>(
      `SELECT id, full_name, phone, status, locale, phone_verified_at, created_at, last_login_at
         FROM core.users WHERE id = $1 AND status <> 'DELETED'`,
      [id],
    );
    if (!user) throw notFound();
    const [businesses, sessions, logins] = await Promise.all([
      this.db.query(
        `SELECT b.id, b.name, r.code AS "roleCode", m.status, m.created_at AS "joinedAt"
           FROM core.business_members m
           JOIN core.businesses b ON b.id = m.business_id
           JOIN core.roles r ON r.id = m.role_id
          WHERE m.user_id = $1 ORDER BY m.created_at`,
        [id],
      ),
      // Une « session » = une famille de jetons de rafraîchissement (un appareil connecté).
      this.db.query(
        `SELECT family_id AS "id", min(created_at) AS "startedAt", max(created_at) AS "lastRefreshAt",
                (array_agg(user_agent ORDER BY created_at DESC))[1] AS "userAgent"
           FROM core.refresh_tokens
          WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > now()
          GROUP BY family_id ORDER BY max(created_at) DESC`,
        [id],
      ),
      this.db.query(
        `SELECT created_at AS "at", success FROM core.login_events
          WHERE user_id = $1 ORDER BY created_at DESC LIMIT 10`,
        [id],
      ),
    ]);
    const { phone, ...rest } = user;
    return {
      ...rest,
      phoneMasked: maskPhone(phone),
      businesses: businesses.rows,
      activeSessions: sessions.rows,
      recentLogins: logins.rows,
    };
  }

  async revealPhone(staff: StaffPrincipal, id: string, reason: string) {
    return this.db.tx(async (tx) => {
      const row = await this.db.one<{ phone: string }>(
        "SELECT phone FROM core.users WHERE id = $1 AND status <> 'DELETED'",
        [id],
        tx,
      );
      if (!row) throw notFound();
      await auditStaff(tx, {
        staffId: staff.staffId,
        action: "admin.user.reveal_phone",
        targetType: "user",
        targetId: id,
        metadata: { reason },
      });
      return { phone: row.phone };
    });
  }

  /** Suspendu = lecture seule dans l'app (le garde de l'API refuse toute modification). */
  async setSuspended(staff: StaffPrincipal, id: string, suspended: boolean, reason: string) {
    const from = suspended ? "ACTIVE" : "SUSPENDED";
    const to = suspended ? "SUSPENDED" : "ACTIVE";
    await this.db.tx(async (tx) => {
      const updated = await tx.query(
        "UPDATE core.users SET status = $3 WHERE id = $1 AND status = $2",
        [id, from, to],
      );
      if (updated.rowCount === 0) {
        const exists = await this.db.one("SELECT 1 FROM core.users WHERE id = $1", [id], tx);
        if (!exists) throw notFound();
        throw conflict(
          "USER_STATUS_UNCHANGED",
          `Le compte n'est pas ${from === "ACTIVE" ? "actif" : "suspendu"}.`,
        );
      }
      await auditStaff(tx, {
        staffId: staff.staffId,
        action: suspended ? "admin.user.suspend" : "admin.user.reactivate",
        targetType: "user",
        targetId: id,
        metadata: { reason },
      });
    });
    await this.states.invalidate(id); // effet immédiat (cache d'état du compte)
    return { id, status: to };
  }

  /** Déconnecte tous les appareils : jetons de rafraîchissement révoqués, jetons d'accès invalidés. */
  async revokeSessions(staff: StaffPrincipal, id: string, reason: string) {
    const revoked = await this.db.tx(async (tx) => {
      const bumped = await tx.query(
        "UPDATE core.users SET token_version = token_version + 1 WHERE id = $1 AND status <> 'DELETED'",
        [id],
      );
      if (bumped.rowCount === 0) throw notFound();
      const r = await tx.query(
        "UPDATE core.refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL",
        [id],
      );
      await auditStaff(tx, {
        staffId: staff.staffId,
        action: "admin.user.revoke_sessions",
        targetType: "user",
        targetId: id,
        metadata: { reason, revokedTokens: r.rowCount },
      });
      return r.rowCount;
    });
    await this.states.invalidate(id);
    return { id, revokedTokens: revoked };
  }
}
