import * as Sentry from "@sentry/node";
import type { ErrorContext, ErrorReporterPort } from "./error-reporter.port.js";
import { scrubEvent } from "./scrub.js";

/**
 * Remontée des erreurs vers Sentry. Seulement les ERREURS : les traces passent par OpenTelemetry
 * (src/instrumentation.ts) — Sentry n'installe donc pas sa propre instrumentation OTel, les deux
 * se marcheraient dessus.
 */
export class SentryErrorReporter implements ErrorReporterPort {
  constructor(opts: { dsn: string; environment: string; release?: string }) {
    Sentry.init({
      dsn: opts.dsn,
      environment: opts.environment,
      ...(opts.release ? { release: opts.release } : {}),
      // Sentry collecte PAR DÉFAUT en-têtes, cookies, corps, paramètres d'URL et infos
      // utilisateur : tout est coupé ici (et scrubEvent repasse derrière, en liste blanche).
      dataCollection: {
        userInfo: false,
        cookies: false,
        httpHeaders: false,
        httpBodies: [],
        urlQueryParams: false,
      },
      // Les traces appartiennent à notre propre SDK OpenTelemetry : Sentry n'enregistre pas de
      // fournisseur de traces concurrent (défaut en v11, explicité ici).
      enableOpenTelemetrySetup: false,
      tracesSampleRate: 0,
      // Pas d'intégrations automatiques (console, http…) : elles fabriquent des fils d'Ariane à
      // partir d'URLs et de logs — on ne veut que les erreurs explicitement signalées.
      defaultIntegrations: false,
      beforeSend: (event) => scrubEvent(event),
    });
  }

  capture(error: unknown, context: ErrorContext = {}): void {
    Sentry.withScope((scope) => {
      if (context.userId) scope.setUser({ id: context.userId });
      const tags: Record<string, string> = { ...context.tags };
      if (context.requestId) tags.requestId = context.requestId;
      if (context.method) tags.method = context.method;
      if (context.route) tags.route = context.route;
      if (context.businessId) tags.businessId = context.businessId;
      if (context.source) tags.source = context.source;
      scope.setTags(tags);
      Sentry.captureException(error);
    });
  }

  async flush(timeoutMs = 2000): Promise<void> {
    await Sentry.flush(timeoutMs);
  }
}
