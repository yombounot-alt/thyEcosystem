/**
 * Port de remontée des erreurs inattendues (docs/blueprint/12-devops-monitoring.md §5) : Sentry
 * quand SENTRY_DSN est défini, rien sinon. Le kernel ne dépend jamais du SDK directement.
 *
 * Règle absolue : aucune donnée personnelle ni secret ne part — ni corps de requête, ni en-têtes,
 * ni numéro de téléphone ; seulement des identifiants techniques (voir ErrorContext).
 */
export const ERROR_REPORTER = "ERROR_REPORTER";

export interface ErrorContext {
  requestId?: string;
  method?: string;
  /** Gabarit de route (`/products/:id`), jamais l'URL réelle (qui peut contenir des données). */
  route?: string;
  userId?: string;
  businessId?: string;
  /** Composant d'origine hors HTTP (ex. `outbox`). */
  source?: string;
  tags?: Record<string, string>;
}

export interface ErrorReporterPort {
  capture(error: unknown, context?: ErrorContext): void;
  /** Vide la file d'envoi (arrêt propre du processus). */
  flush(timeoutMs?: number): Promise<void>;
}

/** Aucune remontée (développement, tests, ou DSN absent). */
export class NoopErrorReporter implements ErrorReporterPort {
  capture(): void {
    /* rien */
  }
  flush(): Promise<void> {
    return Promise.resolve();
  }
}
