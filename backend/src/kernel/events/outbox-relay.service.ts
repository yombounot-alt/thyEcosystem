import { context } from "@opentelemetry/api";
import { suppressTracing } from "@opentelemetry/core";
import {
  Inject,
  Injectable,
  type OnApplicationBootstrap,
  type OnModuleDestroy,
} from "@nestjs/common";
import { CONFIG, type AppConfig } from "../config/config.js";
import { Db } from "../db/db.service.js";
import { AppLogger } from "../logger.js";
import { ERROR_REPORTER, type ErrorReporterPort } from "../observability/error-reporter.port.js";
import { OutboxHandlerRegistry, type OutboxEvent } from "./outbox-handler.js";

/** Durée pendant laquelle un événement réclamé est « à moi » : passé ce délai, un autre relais le reprend. */
const LEASE_SEC = 60;
/** Au-delà, l'événement part en file des morts (`failed_at`) : plus rejoué, mais visible et alertable. */
export const MAX_ATTEMPTS = 8;
const BACKOFF_BASE_SEC = 5;
const BACKOFF_MAX_SEC = 15 * 60;

/** Délai avant la tentative suivante : 5 s, 10 s, 20 s… plafonné à 15 min. */
export function backoffSec(attempts: number): number {
  return Math.min(BACKOFF_MAX_SEC, BACKOFF_BASE_SEC * 2 ** Math.max(0, attempts - 1));
}

/**
 * Relais de la boîte d'envoi transactionnelle (`ops.outbox_events`) vers les consommateurs
 * enregistrés (docs/blueprint/02-architecture.md §6). « Au moins une fois » : l'événement est
 * réclamé par un bail (jamais gardé dans une transaction ouverte pendant que les consommateurs
 * travaillent), acquitté seulement quand tous ont réussi.
 *
 * Plusieurs instances de l'API peuvent tourner : `FOR UPDATE SKIP LOCKED` empêche deux relais de
 * réclamer le même événement. Un processus « worker » dédié, quand il existera, n'aura qu'à appeler
 * `drain()` : la logique ne dépend pas de qui la déclenche.
 *
 * Limite connue : sur Cloud Run, le CPU n'est alloué que pendant une requête (sauf réglage
 * contraire) — la minuterie de fond avance donc au rythme du trafic tant qu'il n'y a pas de worker.
 */
@Injectable()
export class OutboxRelayService implements OnApplicationBootstrap, OnModuleDestroy {
  private timer: NodeJS.Timeout | undefined;
  private inFlight: Promise<void> | undefined;
  private stopped = false;

  constructor(
    private readonly db: Db,
    private readonly registry: OutboxHandlerRegistry,
    private readonly logger: AppLogger,
    @Inject(CONFIG) private readonly cfg: AppConfig,
    @Inject(ERROR_REPORTER) private readonly reporter: ErrorReporterPort,
  ) {}

  onApplicationBootstrap(): void {
    if (!this.cfg.outbox.relayEnabled) return;
    this.timer = setInterval(() => {
      if (this.inFlight || this.stopped) return; // un seul tour à la fois par instance
      // Boucle de fond, hors de toute requête : ses interrogations périodiques (une toutes les
      // quelques secondes, même sans rien à traiter) ne sont pas tracées — elles noieraient les
      // vraies traces et coûteraient cher. Sans SDK OpenTelemetry actif, c'est sans effet.
      this.inFlight = context
        .with(suppressTracing(context.active()), () => this.drain())
        .then(() => undefined)
        .catch((e: unknown) => {
          this.logger.error(
            `outbox: tour du relais en erreur : ${e instanceof Error ? e.message : String(e)}`,
            undefined,
            "outbox",
          );
        })
        .finally(() => {
          this.inFlight = undefined;
        });
    }, this.cfg.outbox.pollIntervalMs);
    this.timer.unref(); // ne retient jamais l'arrêt du processus
  }

  async onModuleDestroy(): Promise<void> {
    this.stopped = true;
    if (this.timer) clearInterval(this.timer);
    await this.inFlight; // le pool ne doit pas se fermer sous un tour en cours
  }

  /** Traite les événements prêts jusqu'à épuisement (ou `max`). Renvoie le nombre traités. */
  async drain(max = 100): Promise<number> {
    let processed = 0;
    while (processed < max && (await this.dispatchOne())) processed++;
    return processed;
  }

  /** Traite UN événement prêt ; false s'il n'y en a aucun. */
  async dispatchOne(): Promise<boolean> {
    const event = await this.claim();
    if (!event) return false;
    try {
      for (const handler of this.registry.for(event.eventType)) {
        if (await this.alreadyProcessed(handler.consumer, event.id)) continue;
        await handler.handle(event);
        await this.db.query(
          `INSERT INTO ops.processed_events (consumer, event_id) VALUES ($1, $2)
           ON CONFLICT DO NOTHING`,
          [handler.consumer, event.id],
        );
      }
      // Aucun consommateur intéressé : rien à faire, l'événement est simplement acquitté.
      await this.db.query(
        "UPDATE ops.outbox_events SET published_at = now(), last_error = NULL WHERE id = $1",
        [event.id],
      );
    } catch (error) {
      await this.fail(event, error);
    }
    return true;
  }

  private async claim(): Promise<(OutboxEvent & { attempts: number }) | null> {
    return this.db.one<OutboxEvent & { attempts: number }>(
      `UPDATE ops.outbox_events e
          SET attempts = e.attempts + 1,
              next_attempt_at = now() + make_interval(secs => $1)
        WHERE e.id = (
                SELECT id FROM ops.outbox_events
                 WHERE published_at IS NULL AND failed_at IS NULL AND next_attempt_at <= now()
                 ORDER BY occurred_at
                 FOR UPDATE SKIP LOCKED
                 LIMIT 1)
    RETURNING e.id, e.event_type, e.aggregate_type, e.aggregate_id, e.business_id, e.payload,
              e.occurred_at, e.attempts`,
      [LEASE_SEC],
    );
  }

  private async alreadyProcessed(consumer: string, eventId: string): Promise<boolean> {
    const row = await this.db.one(
      "SELECT 1 FROM ops.processed_events WHERE consumer = $1 AND event_id = $2",
      [consumer, eventId],
    );
    return row !== null;
  }

  private async fail(event: { id: string; eventType: string; attempts: number }, error: unknown) {
    const message = (error instanceof Error ? error.message : String(error)).slice(0, 300);
    const dead = event.attempts >= MAX_ATTEMPTS;
    await this.db.query(
      `UPDATE ops.outbox_events
          SET last_error = $2,
              next_attempt_at = now() + make_interval(secs => $3),
              failed_at = CASE WHEN $4::boolean THEN now() END
        WHERE id = $1`,
      [event.id, message, backoffSec(event.attempts), dead],
    );
    // File des morts : plus aucun nouvel essai — c'est un incident à traiter, donc remonté.
    if (dead)
      this.reporter.capture(error, {
        source: "outbox",
        tags: { eventType: event.eventType, eventId: event.id },
      });
    this.logger.error(
      `outbox: ${event.eventType} (${event.id}) tentative ${event.attempts}/${MAX_ATTEMPTS} : ${message}${dead ? " — file des morts" : ""}`,
      undefined,
      "outbox",
    );
  }
}
