import type { BizTx } from "../biz-prisma.service.js";

/**
 * Écrit un événement dans l'outbox du kernel (`ops.outbox_events`) DANS la transaction Prisma en
 * cours : il n'existe que si le changement métier est validé (même garantie qu'OutboxService, qui
 * attend un client `pg` — ici on reste sur la connexion de la transaction Prisma).
 */
export async function emitBizEvent(
  tx: BizTx,
  businessId: string,
  eventType: string,
  aggregateType: string,
  aggregateId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  await tx.$executeRaw`
    INSERT INTO ops.outbox_events (event_type, aggregate_type, aggregate_id, business_id, payload)
    VALUES (${eventType}, ${aggregateType}, ${aggregateId}::uuid, ${businessId}::uuid,
            ${JSON.stringify({ businessId, ...payload })}::jsonb)`;
}
