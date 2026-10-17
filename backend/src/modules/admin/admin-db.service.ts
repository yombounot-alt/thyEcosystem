import { Inject, Injectable } from "@nestjs/common";
import { CONFIG, type AppConfig } from "../../kernel/config/config.js";
import { Db, type Queryable } from "../../kernel/db/db.service.js";

/**
 * Accès base de la console d'administration, sous le rôle PostgreSQL `thy_admin_app` — distinct de
 * celui de l'app : ses droits sont accordés table par table (migration 0010), en lecture pour
 * l'essentiel. Même interface que `Db` (requêtes, transactions).
 */
@Injectable()
export class AdminDb extends Db {
  constructor(@Inject(CONFIG) cfg: AppConfig) {
    super({ ...cfg, databaseUrl: cfg.admin.databaseUrl, dbPoolMax: 5 });
  }
}

/** Entrée du journal d'audit par un membre du staff (auteur de type `staff`). */
export async function auditStaff(
  q: Queryable,
  e: {
    staffId: string | null;
    action: string;
    targetType?: string;
    targetId?: string;
    ipHash?: Buffer | null;
    metadata?: Record<string, unknown>;
  },
): Promise<void> {
  await q.query(
    `INSERT INTO ops.audit_logs (actor_id, actor_type, action, target_type, target_id, ip_hash, metadata)
     VALUES ($1, 'staff', $2, $3, $4, $5, $6)`,
    [
      e.staffId,
      e.action,
      e.targetType ?? null,
      e.targetId ?? null,
      e.ipHash ?? null,
      JSON.stringify(e.metadata ?? {}),
    ],
  );
}
