// Configuration typée, validée au démarrage. En production, l'application REFUSE de démarrer
// avec des secrets absents, faibles ou égaux aux valeurs de développement.
// Référence : docs/blueprint/02-architecture.md §5.4, docs/blueprint/11-security.md §3.6.

export const CONFIG = "APP_CONFIG";

export interface AppConfig {
  env: "development" | "test" | "production";
  port: number;
  trustProxy: boolean;
  corsOrigins: string[];
  /** Connexion applicative (`thy_app`, NOBYPASSRLS) — utilisée par toutes les requêtes runtime. */
  databaseUrl: string;
  /** Connexion propriétaire du schéma (`thy_migrator`) — utilisée UNIQUEMENT par le migrateur.
   * Distincte de `databaseUrl` par construction : `thy_app` n'a aucun droit de DDL, et un
   * superutilisateur (comme `thy_migrator`) contourne toujours RLS, donc le runtime ne doit
   * jamais s'y connecter (voir docs/blueprint/03-database.md §1, ADR-004). */
  migratorDatabaseUrl: string;
  dbPoolMax: number;
  redisUrl: string;
  jwt: { secret: string; issuer: string; accessTtlSec: number; refreshTtlDays: number };
  hmacPepper: string;
  defaultCountry: string;
  defaultCurrency: string;
  sms: { driver: "console" };
  rateLimitEnabled: boolean;
}

const DEV_SECRET = "dev-only-secret-change-me-dev-only-secret-change-me";

function num(v: string | undefined, def: number): number {
  if (v === undefined || v === "") return def;
  const n = Number(v);
  if (!Number.isFinite(n)) throw new Error(`Valeur numérique invalide: "${v}"`);
  return n;
}
function bool(v: string | undefined, def: boolean): boolean {
  if (v === undefined || v === "") return def;
  return ["1", "true", "yes"].includes(v.toLowerCase());
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const nodeEnv = (env.NODE_ENV ?? "development") as AppConfig["env"];
  if (!["development", "test", "production"].includes(nodeEnv))
    throw new Error(`NODE_ENV invalide: ${nodeEnv}`);

  const cfg: AppConfig = {
    env: nodeEnv,
    port: num(env.PORT, 3000),
    trustProxy: bool(env.TRUST_PROXY, false),
    corsOrigins: (env.CORS_ORIGINS ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
    databaseUrl: env.DATABASE_URL ?? "postgres://thy_app:changeme@localhost:5435/thy",
    migratorDatabaseUrl:
      env.MIGRATOR_DATABASE_URL ?? "postgres://thy_migrator:changeme@localhost:5435/thy",
    dbPoolMax: num(env.DB_POOL_MAX, 10),
    redisUrl: env.REDIS_URL ?? "redis://localhost:6379",
    jwt: {
      // `||` et non `??` : une variable présente mais VIDE (cas de .env.example, à remplir en
      // production) doit retomber sur le défaut de dev, pas produire une clé de signature vide.
      secret: env.JWT_SECRET || DEV_SECRET,
      issuer: env.JWT_ISSUER || "thy-ecosystem",
      accessTtlSec: num(env.ACCESS_TTL_SEC, 15 * 60),
      refreshTtlDays: num(env.REFRESH_TTL_DAYS, 30),
    },
    hmacPepper: env.HMAC_PEPPER || DEV_SECRET + "-pepper",
    defaultCountry: (env.DEFAULT_COUNTRY ?? "GN").toUpperCase(),
    defaultCurrency: (env.DEFAULT_CURRENCY ?? "GNF").toUpperCase(),
    sms: { driver: "console" },
    rateLimitEnabled: bool(env.RATE_LIMIT_ENABLED, true),
  };

  validateConfig(cfg);
  return cfg;
}

export function validateConfig(cfg: AppConfig): void {
  if (cfg.env !== "production") return;
  const weak = (s: string) => s.length < 32 || s.includes("dev-only");
  const errors: string[] = [];
  if (weak(cfg.jwt.secret)) errors.push("JWT_SECRET absent/faible (≥ 32 caractères requis)");
  if (weak(cfg.hmacPepper)) errors.push("HMAC_PEPPER absent/faible");
  if (cfg.migratorDatabaseUrl === cfg.databaseUrl)
    errors.push(
      "MIGRATOR_DATABASE_URL doit être distinct de DATABASE_URL (rôles séparés, voir ADR-004)",
    );
  if (cfg.sms.driver === "console")
    errors.push('SMS_DRIVER ne peut pas être "console" en production');
  if (!cfg.rateLimitEnabled)
    errors.push("RATE_LIMIT_ENABLED ne peut pas être désactivé en production");
  if (errors.length)
    throw new Error(`Configuration de production invalide:\n - ${errors.join("\n - ")}`);
}
