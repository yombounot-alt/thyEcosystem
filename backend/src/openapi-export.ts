// Exporte le contrat OpenAPI dans docs/api/openapi.json (versionné : chaque changement d'API se
// voit dans la revue de code). Lancé sur le code COMPILÉ (`nest build` applique le plugin Swagger
// qui déduit les schémas des DTO) : `pnpm --filter @thy/backend run openapi:export`.
// N'ouvre aucune connexion utile : la construction du document n'exécute aucune requête.
import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { AppModule } from "./app.module.js";
import { buildOpenApiDocument } from "./openapi.js";

process.env.OUTBOX_RELAY_ENABLED = "false";
const out = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../docs/api/openapi.json",
);

const app = await NestFactory.create(AppModule, { logger: false });
app.setGlobalPrefix("api/v1", { exclude: ["health/live", "health/ready"] });
const document = buildOpenApiDocument(app);
mkdirSync(path.dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(document, null, 2) + "\n");
await app.close();
process.stdout.write(
  `Contrat OpenAPI écrit : ${out} (${Object.keys(document.paths).length} chemins)\n`,
);
