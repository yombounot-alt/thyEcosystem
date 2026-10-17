import { loadConfig, requireMigratorUrl } from "../kernel/config/config.js";
import { runMigrations } from "./migrate.js";

const cfg = loadConfig();
const applied = await runMigrations(requireMigratorUrl(cfg));
console.log(applied.length ? `Migrations appliquées: ${applied.join(", ")}` : "Base à jour.");
