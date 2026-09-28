import { Injectable } from "@nestjs/common";

/** Un événement de `ops.outbox_events`, tel que le relais le remet aux consommateurs. */
export interface OutboxEvent {
  id: string;
  eventType: string;
  aggregateType: string;
  aggregateId: string | null;
  businessId: string | null;
  payload: Record<string, unknown>;
  occurredAt: Date;
}

/**
 * Consommateur d'événements métier. Le relais est « au moins une fois » : un événement peut être
 * remis plusieurs fois (échec d'un autre consommateur, plantage avant l'acquittement) — `handle`
 * doit donc être idempotent (voir `dedupe_key` des notifications).
 */
export interface OutboxEventHandler {
  /** Nom stable du consommateur (clé de `ops.processed_events`) — ne jamais le renommer. */
  readonly consumer: string;
  readonly eventTypes: readonly string[];
  handle(event: OutboxEvent): Promise<void>;
}

/**
 * Les modules y inscrivent leurs consommateurs au démarrage ; le relais ne connaît que ce registre,
 * jamais un module métier (le kernel ne dépend pas des modules au-dessus de lui).
 */
@Injectable()
export class OutboxHandlerRegistry {
  private readonly handlers: OutboxEventHandler[] = [];

  register(handler: OutboxEventHandler): void {
    if (this.handlers.some((h) => h.consumer === handler.consumer))
      throw new Error(`Consommateur d'outbox déjà enregistré : ${handler.consumer}`);
    this.handlers.push(handler);
  }

  for(eventType: string): OutboxEventHandler[] {
    return this.handlers.filter((h) => h.eventTypes.includes(eventType));
  }
}
