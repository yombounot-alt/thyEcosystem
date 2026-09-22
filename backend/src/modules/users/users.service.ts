import { Injectable } from "@nestjs/common";
import { Db } from "../../kernel/db/db.service.js";
import { notFound } from "../../kernel/errors.js";
import type { UpdateMeDto } from "./dto.js";

const ME_COLUMNS = `id, phone, email, full_name AS "fullName", locale, timezone,
                     (phone_verified_at IS NOT NULL) AS "phoneVerified", created_at AS "createdAt"`;

@Injectable()
export class UsersService {
  constructor(private readonly db: Db) {}

  async me(userId: string) {
    const row = await this.db.one(`SELECT ${ME_COLUMNS} FROM core.users WHERE id = $1`, [userId]);
    if (!row) throw notFound();
    return row;
  }

  async update(userId: string, dto: UpdateMeDto) {
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
    if (sets.length === 0) return this.me(userId);
    await this.db.query(`UPDATE core.users SET ${sets.join(", ")} WHERE id = $1`, params);
    return this.me(userId);
  }

  /** Entreprises dont l'utilisateur est membre actif — sert la liste "mes entreprises" côté app. */
  async myBusinesses(userId: string) {
    return this.db
      .withTenant({ userId }, (tx) =>
        tx.query(
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
