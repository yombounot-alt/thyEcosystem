// Traces OpenTelemetry (docs/blueprint/12-devops-monitoring.md §5), chargées AVANT l'application :
//   node --import ./dist/instrumentation.js dist/main.js
// Inactif tant que OTEL_EXPORTER_OTLP_ENDPOINT n'est pas défini (aucun envoi implicite). Les spans
// partent en OTLP/HTTP vers un collecteur (infra/docker/otel-collector.yml en local).
//
// Confidentialité : ni valeurs des requêtes SQL, ni arguments Redis (les clés de limitation de
// débit contiennent une IP), ni corps HTTP — seulement la forme des opérations et leurs durées.
import { register } from "node:module";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { ExpressInstrumentation } from "@opentelemetry/instrumentation-express";
import { HttpInstrumentation } from "@opentelemetry/instrumentation-http";
import { IORedisInstrumentation } from "@opentelemetry/instrumentation-ioredis";
import { PgInstrumentation } from "@opentelemetry/instrumentation-pg";
import { resourceFromAttributes } from "@opentelemetry/resources";
import { NodeSDK } from "@opentelemetry/sdk-node";
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from "@opentelemetry/semantic-conventions";

/** Sondes de santé : appelées toutes les quelques secondes, sans intérêt en trace. */
export const isHealthProbe = (url: string | undefined) => url?.startsWith("/health/") ?? false;

/** Redis : le nom de la commande seulement (`INCR`, `GET`…), jamais ses arguments. */
export const redisStatement = (command: string) => command.toUpperCase();

if (process.env.OTEL_EXPORTER_OTLP_ENDPOINT) {
  // L'application est en modules ES : sans ce hook, seules les bibliothèques chargées par
  // `require` (CommonJS) seraient instrumentées — ni Express ni ioredis ne l'étaient.
  register("@opentelemetry/instrumentation/hook.mjs", import.meta.url);
  const sdk = new NodeSDK({
    resource: resourceFromAttributes({
      // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing -- vide ⇒ défaut
      [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || "thy-backend",
      // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing -- vide ⇒ défaut
      [ATTR_SERVICE_VERSION]: process.env.APP_RELEASE || process.env.K_REVISION || "dev",
    }),
    // Lit OTEL_EXPORTER_OTLP_ENDPOINT (+ /v1/traces) et OTEL_EXPORTER_OTLP_HEADERS.
    traceExporter: new OTLPTraceExporter(),
    instrumentations: [
      new HttpInstrumentation({ ignoreIncomingRequestHook: (req) => isHealthProbe(req.url) }),
      new ExpressInstrumentation(),
      // ignoreConnectSpans : une span par emprunt de connexion au pool n'apporte que du bruit.
      new PgInstrumentation({ enhancedDatabaseReporting: false, ignoreConnectSpans: true }),
      new IORedisInstrumentation({ dbStatementSerializer: redisStatement }),
    ],
  });
  sdk.start();
  const stop = () => {
    void sdk.shutdown();
  };
  process.once("SIGTERM", stop);
  process.once("SIGINT", stop);
}
