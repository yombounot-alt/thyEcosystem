import { Inject, Module, type OnApplicationShutdown } from "@nestjs/common";
import { CONFIG, type AppConfig } from "../config/config.js";
import {
  ERROR_REPORTER,
  NoopErrorReporter,
  type ErrorReporterPort,
} from "./error-reporter.port.js";
import { SentryErrorReporter } from "./sentry-error-reporter.adapter.js";

/** Remontée d'erreurs : Sentry si SENTRY_DSN est défini, sinon rien (aucun envoi implicite). */
@Module({
  providers: [
    {
      provide: ERROR_REPORTER,
      inject: [CONFIG],
      useFactory: (cfg: AppConfig): ErrorReporterPort => {
        const o = cfg.observability;
        return o.sentryDsn
          ? new SentryErrorReporter({
              dsn: o.sentryDsn,
              environment: o.environment,
              ...(o.release ? { release: o.release } : {}),
            })
          : new NoopErrorReporter();
      },
    },
  ],
  exports: [ERROR_REPORTER],
})
export class ObservabilityModule implements OnApplicationShutdown {
  constructor(@Inject(ERROR_REPORTER) private readonly reporter: ErrorReporterPort) {}

  /** Les dernières erreurs partent avant l'arrêt de l'instance (Cloud Run coupe vite). */
  async onApplicationShutdown(): Promise<void> {
    await this.reporter.flush(2000);
  }
}
