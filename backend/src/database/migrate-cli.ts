import { loadConfig } from "../kernel/config/config.js";
import { runMigrations } from "./migrate.js";

const cfg = loadConfig();
const applied = await runMigrations(cfg.migratorDatabaseUrl);
console.log(applied.length ? `Migrations appliquées: ${applied.join(", ")}` : "Base à jour.");
