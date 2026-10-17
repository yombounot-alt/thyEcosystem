import { Injectable } from "@nestjs/common";
import { clampLimit, decodeCursor, encodeCursor } from "../../kernel/util.js";
import { AdminDb } from "./admin-db.service.js";
import type { AuditQuery } from "./dto.js";

/** Journal d'audit (append-only) : recherche filtrée, du plus récent au plus ancien. */
@Injectable()
export class AdminAuditService {
  constructor(private readonly db: AdminDb) {}

  async search(q: AuditQuery) {
    const n = clampLimit(q.limit, 50, 100);
    const after = decodeCursor<{ id: number }>(q.cursor);
    const params: unknown[] = [];
    const where: string[] = [];
    const add = (sql: string, value: unknown) => {
      params.push(value);
      where.push(sql.replace("?", `$${params.length}`));
    };
    if (q.action) add("a.action LIKE ?", `${q.action}%`);
    if (q.actorType) add("a.actor_type = ?", q.actorType);
    if (q.actorId) add("a.actor_id::text = ?", q.actorId);
    if (q.targetId) add("a.target_id = ?", q.targetId);
    if (q.from) add("a.created_at >= ?", q.from);
    if (q.to) add("a.created_at < ?", q.to);
    if (after) add("a.id < ?", after.id);
    params.push(n + 1);
    const rows = await this.db.query<{
      id: number;
      createdAt: Date;
      actorType: string;
      actorId: string | null;
      actorLabel: string | null;
      action: string;
      targetType: string | null;
      targetId: string | null;
      metadata: Record<string, unknown>;
    }>(
      `SELECT a.id, a.created_at, a.actor_type, a.actor_id,
              CASE a.actor_type WHEN 'staff' THEN s.email ELSE u.full_name END AS actor_label,
              a.action, a.target_type, a.target_id, a.metadata
         FROM ops.audit_logs a
         LEFT JOIN core.staff_users s ON a.actor_type = 'staff' AND s.id = a.actor_id
         LEFT JOIN core.users u ON a.actor_type = 'user' AND u.id = a.actor_id
        ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
        ORDER BY a.id DESC LIMIT $${params.length}`,
      params,
    );
    const items = rows.rows.slice(0, n);
    const last = items.at(-1);
    return {
      items,
      nextCursor: rows.rows.length > n && last ? encodeCursor({ id: last.id }) : null,
    };
  }
}
