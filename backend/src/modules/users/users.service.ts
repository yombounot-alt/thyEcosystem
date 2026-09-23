import { Injectable } from "@nestjs/common";
import { PermissionsService } from "../../kernel/auth/permissions.service.js";
import { Db } from "../../kernel/db/db.service.js";
import { notFound } from "../../kernel/errors.js";
import type { UpdateMeDto } from "./dto.js";

export interface BusinessSummaryRow {
  id: string;
  name: string;
  businessType: string | null;
  currency: string;
  roleCode: string;
}

const ME_COLUMNS = `id, phone, email, full_name AS "fullName", locale, timezone,
                     (phone_verified_at IS NOT NULL) AS "phoneVerified", created_at AS "createdAt"`;

@Injectable()
export class UsersService {
  constructor(
    private readonly db: Db,
    private readonly permissions: PermissionsService,
  ) {}

  /**
   * Profil + contexte : ce dont l'app a besoin pour démarrer en un seul appel. `activeBusinessId` est
   * l'entreprise portée par le jeton, seulement si l'utilisateur en est encore membre. Les
   * permissions sont celles EFFECTIVES (rôle + surcharges) : l'app s'en sert pour masquer des
   * actions, l'autorité reste le serveur qui les relit à chaque requête.
   */
  async me(userId: string, activeClaim?: string | null) {
    const row = await this.db.one(`SELECT ${ME_COLUMNS} FROM core.users WHERE id = $1`, [userId]);
    if (!row) throw notFound();
    const businesses = await Promise.all(
      (await this.myBusinesses(userId)).map(async (b) => {
        const membership = await this.permissions.getMembership(userId, b.id);
        const effective = membership
          ? await this.permissions.getEffectivePermissions(membership)
          : [];
        return { ...b, permissions: [...effective].sort() };
      }),
    );
    const activeBusinessId =
      activeClaim && businesses.some((b) => b.id === activeClaim) ? activeClaim : null;
    return { ...row, activeBusinessId, businesses };
  }

  async update(userId: string, dto: UpdateMeDto, activeClaim?: string | null) {
    const sets: string[] = [];
    const params: unknown[] = [userId];
    if (dto.fullName !== undefined) {
      params.push(dto.fullName.trim());
      sets.push(`full_name = $${params.length}`);
    }
    if (dto.locale !== undefined) {
      params.push(dto.locale);
      sets.push(`locale = $${params.length}`);
    }
    if (dto.timezone !== undefined) {
      params.push(dto.timezone);
      sets.push(`timezone = $${params.length}`);
    }
    if (sets.length > 0)
      await this.db.query(`UPDATE core.users SET ${sets.join(", ")} WHERE id = $1`, params);
    return this.me(userId, activeClaim);
  }

  /** Entreprises dont l'utilisateur est membre actif — sert la liste "mes entreprises" côté app. */
  async myBusinesses(userId: string) {
    return this.db
      .withTenant({ userId }, (tx) =>
        tx.query<BusinessSummaryRow>(
          `SELECT b.id, b.name, b.business_type AS "businessType", b.currency, r.code AS "roleCode"
           FROM core.business_members m
           JOIN core.businesses b ON b.id = m.business_id
           JOIN core.roles r ON r.id = m.role_id
          WHERE m.user_id = $1 AND m.status = 'ACTIVE'
          ORDER BY b.created_at`,
          [userId],
        ),
      )
      .then((r) => r.rows);
  }
}
