import { existsSync } from "node:fs";

// Les tests e2e visent la pile de développement (docker compose) : on charge backend/.env sans
// écraser ce que l'environnement (CI) a déjà défini.
if (existsSync(".env")) process.loadEnvFile(".env");

// Les suites créent des dizaines de comptes depuis la même IP : la limitation de débit est
// désactivée ici, et exercée explicitement par la suite auth (qui la réactive).
process.env.RATE_LIMIT_ENABLED = "false";
process.env.STORAGE_LOCAL_PATH ||= "./uploads-test";
process.env.NODE_ENV = "test";
