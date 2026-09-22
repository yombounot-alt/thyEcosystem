import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module.js";
import { configureApp } from "./bootstrap.js";
import { AppLogger } from "./kernel/logger.js";
import { CONFIG, type AppConfig } from "./kernel/config/config.js";
import { runMigrations } from "./database/migrate.js";

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bodyParser: false, bufferLogs: true });
  const cfg = app.get<AppConfig>(CONFIG);
  app.useLogger(app.get(AppLogger));
  await runMigrations(cfg.migratorDatabaseUrl); // idempotent ; verrou consultatif ⇒ sûr avec plusieurs instances
  configureApp(app, cfg);
  await app.listen(cfg.port);
  app.get(AppLogger).log(`API THY à l'écoute sur :${cfg.port} (${cfg.env})`, "bootstrap");
}
await bootstrap();
