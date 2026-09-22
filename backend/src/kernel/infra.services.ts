import { Injectable } from "@nestjs/common";
import { createHash } from "node:crypto";
import { Db, type Queryable } from "./db/db.service.js";
import { conflict, unprocessable } from "./errors.js";

/** Journal d'audit immuable : qui a fait quoi, sur quelle cible. Référence : docs/blueprint/11-security.md §3.10. */
@Injectable()
export class AuditService {
  async log(
    q: Queryable,
    e: {
      actorId?: string | null;
      action: string;
      targetType?: string;
      targetId?: string;
      ipHash?: Buffer | null;
      metadata?: Record<string, unknown>;
    },
  ): Promise<void> {
    await q.query(
      `INSERT INTO ops.audit_logs (actor_id, action, target_type, target_id, ip_hash, metadata)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        e.actorId ?? null,
        e.action,
        e.targetType ?? null,
        e.targetId ?? null,
        e.ipHash ?? null,
        JSON.stringify(e.metadata ?? {}),
      ],
    );
  }
}

/**
 * Transactional outbox : l'événement est écrit dans la MÊME transaction que le changement métier.
 * Référence : docs/blueprint/02-architecture.md §6.
 */
@Injectable()
export class OutboxService {
  async emit(
    q: Queryable,
    type: string,
    aggregateType: string,
    aggregateId: string | null,
    payload: Record<string, unknown> = {},
    businessId?: string | null,
  ): Promise<void> {
    await q.query(
      `INSERT INTO ops.outbox_events (event_type, aggregate_type, aggregate_id, business_id, payload)
       VALUES ($1, $2, $3, $4, $5)`,
      [type, aggregateType, aggregateId, businessId ?? null, JSON.stringify(payload)],
    );
  }
}

/**
 * Idempotence des créations (header Idempotency-Key). Référence : docs/blueprint/05-api.md §3.3.
 */
@Injectable()
export class IdempotencyService {
  constructor(private readonly db: Db) {}

  async run<T>(
    userId: string,
    key: string | undefined,
    endpoint: string,
    body: unknown,
    fn: () => Promise<{ status: number; body: T }>,
  ): Promise<{ status: number; body: T }> {
    if (!key || key.length < 8 || key.length > 128) {
      throw unprocessable(
        "IDEMPOTENCY_KEY_REQUIRED",
        "Le header Idempotency-Key (8 à 128 caractères) est obligatoire",
      );
    }
    const hash = createHash("sha256")
      .update(JSON.stringify(body ?? null))
      .digest();
    const inserted = await this.db.query(
      `INSERT INTO ops.idempotency_keys (user_id, key, endpoint, request_hash) VALUES ($1, $2, $3, $4)
       ON CONFLICT DO NOTHING`,
      [userId, key, endpoint, hash],
    );
    if (inserted.rowCount === 0) {
      const row = await this.db.one<{
        requestHash: Buffer;
        responseStatus: number | null;
        responseBody: T | null;
      }>(
        `SELECT request_hash, response_status, response_body FROM ops.idempotency_keys WHERE user_id = $1 AND key = $2 AND endpoint = $3`,
        [userId, key, endpoint],
      );
      if (!row) throw conflict("IDEMPOTENCY_IN_PROGRESS", "Requête en cours de traitement");
      if (!row.requestHash.equals(hash))
        throw unprocessable(
          "IDEMPOTENCY_KEY_REUSED",
          "Cette clé a déjà été utilisée avec un contenu différent",
        );
      if (row.responseStatus === null)
        throw conflict("IDEMPOTENCY_IN_PROGRESS", "Requête en cours de traitement");
      return { status: row.responseStatus, body: row.responseBody as T };
    }
    try {
      const result = await fn();
      await this.db.query(
        `UPDATE ops.idempotency_keys SET response_status = $4, response_body = $5 WHERE user_id = $1 AND key = $2 AND endpoint = $3`,
        [userId, key, endpoint, result.status, JSON.stringify(result.body)],
      );
      return result;
    } catch (e) {
      await this.db.query(
        `DELETE FROM ops.idempotency_keys WHERE user_id = $1 AND key = $2 AND endpoint = $3`,
        [userId, key, endpoint],
      );
      throw e;
    }
  }
}
