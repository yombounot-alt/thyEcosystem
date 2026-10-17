import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module.js";
import { configureApp } from "./bootstrap.js";
import { AppLogger } from "./kernel/logger.js";
import { CONFIG, type AppConfig } from "./kernel/config/config.js";
import { runMigrations, startupMigrationUrl } from "./database/migrate.js";

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bodyParser: false, bufferLogs: true });
  const cfg = app.get<AppConfig>(CONFIG);
  app.useLogger(app.get(AppLogger));
  // Développement seulement (voir startupMigrationUrl) ; verrou consultatif ⇒ sûr à plusieurs instances.
  const migrateUrl = startupMigrationUrl(cfg);
  if (migrateUrl) await runMigrations(migrateUrl);
  configureApp(app, cfg);
  await app.listen(cfg.port);
  app.get(AppLogger).log(`API THY à l'écoute sur :${cfg.port} (${cfg.env})`, "bootstrap");
}
await bootstrap();
