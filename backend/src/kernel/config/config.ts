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
  /**
   * `fixedOtp` : code OTP constant pour le développement et les tests d'intégration (mobile,
   * scripts) — l'adaptateur `console` n'envoie aucun SMS, il n'y a donc rien à protéger ; refusé en
   * production.
   */
  sms: { driver: "console"; fixedOtp?: string };
  /**
   * Stockage de fichiers (voir StoragePort) : disque local en développement, S3-compatible (RustFS,
   * ou Cloud Storage via son interop S3 — ADR-012) ailleurs. Le disque local est refusé en production.
   */
  storage: { driver: "local" | "s3"; localPath: string; s3?: S3Config };
  rateLimitEnabled: boolean;
  /**
   * Relais d'outbox : dépile les événements métier vers leurs consommateurs (notifications…).
   * Désactivé dans les tests (qui le pilotent à la main, sans minuterie de fond).
   */
  outbox: { relayEnabled: boolean; pollIntervalMs: number };
  /** Notifications push : seul l'adaptateur `console` existe (aucun projet Firebase réel encore). */
  push: { driver: "console" };
  /** Contrat OpenAPI servi sur /api/v1/openapi.json (défaut : oui hors production). */
  openApiEnabled: boolean;
  /**
   * Observabilité (docs/blueprint/12-devops-monitoring.md §5). Erreurs → Sentry si `SENTRY_DSN` ;
   * traces → OTLP si `OTEL_EXPORTER_OTLP_ENDPOINT` (voir src/instrumentation.ts). Rien n'est
   * envoyé tant que ces variables sont absentes.
   */
  observability: {
    sentryDsn?: string;
    /** Étiquette d'environnement des événements (`staging`, `production`…). */
    environment: string;
    /** Version déployée (SHA de l'image, révision Cloud Run…). */
    release?: string;
  };
  /** Console d'administration (docs/blueprint/09-admin.md, L0.11). */
  admin: AdminConfig;
}

export interface AdminConfig {
  /** Connexion `thy_admin_app` (droits explicites, voir migration 0010) — jamais celle de l'app. */
  databaseUrl: string;
  /** Clé AES-256 (32 octets, base64) qui chiffre les secrets TOTP du staff en base. */
  totpKey: Buffer;
  /** Cookie de session `Secure` (https uniquement) : toujours en production. */
  cookieSecure: boolean;
  /** Session staff : inactivité maximale, puis durée de vie absolue. */
  sessionIdleMinutes: number;
  sessionMaxHours: number;
  /** Échecs (mot de passe ou code TOTP) avant verrouillage, et durée du verrouillage. */
  maxFailedLogins: number;
  lockMinutes: number;
}

export interface S3Config {
  /** Ex. `http://localhost:9002` (RustFS en local) ou `https://storage.googleapis.com` (GCS). */
  endpoint: string;
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
  /** Adressage `endpoint/bucket/clé` (RustFS, GCS) plutôt que `bucket.endpoint/clé`. */
  forcePathStyle: boolean;
}

const DEV_SECRET = "dev-only-secret-change-me-dev-only-secret-change-me";
/** Clé TOTP de développement (32 octets) : refusée en production. */
const DEV_TOTP_KEY = Buffer.alloc(32, 7).toString("base64");

function loadAdmin(env: NodeJS.ProcessEnv, nodeEnv: AppConfig["env"]): AdminConfig {
  // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing -- vide ⇒ défaut de dev
  const keyB64 = env.ADMIN_TOTP_KEY || DEV_TOTP_KEY;
  const totpKey = Buffer.from(keyB64, "base64");
  if (totpKey.length !== 32)
    throw new Error("ADMIN_TOTP_KEY doit contenir 32 octets encodés en base64");
  return {
    databaseUrl: env.ADMIN_DATABASE_URL ?? "postgres://thy_admin_app:changeme@localhost:5435/thy",
    totpKey,
    cookieSecure: bool(env.ADMIN_COOKIE_SECURE, nodeEnv === "production"),
    sessionIdleMinutes: num(env.ADMIN_SESSION_IDLE_MINUTES, 30),
    sessionMaxHours: num(env.ADMIN_SESSION_MAX_HOURS, 8),
    maxFailedLogins: num(env.ADMIN_MAX_FAILED_LOGINS, 5),
    lockMinutes: num(env.ADMIN_LOCK_MINUTES, 15),
  };
}

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

function loadStorage(env: NodeJS.ProcessEnv): AppConfig["storage"] {
  const driver = (env.STORAGE_DRIVER ?? "local").toLowerCase();
  if (driver !== "local" && driver !== "s3")
    throw new Error(`STORAGE_DRIVER invalide: "${driver}" (local ou s3)`);
  // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing -- voir plus bas (JWT_SECRET)
  const localPath = env.STORAGE_LOCAL_PATH || "./uploads";
  if (driver === "local") return { driver, localPath };
  const missing: string[] = [];
  const need = (name: string, value: string | undefined): string => {
    if (!value) missing.push(name);
    return value ?? "";
  };
  const endpoint = need("endpoint", env.S3_ENDPOINT);
  const bucket = need("bucket", env.S3_BUCKET);
  const accessKeyId = need("accessKeyId", env.S3_ACCESS_KEY_ID);
  const secretAccessKey = need("secretAccessKey", env.S3_SECRET_ACCESS_KEY);
  if (missing.length)
    throw new Error(`STORAGE_DRIVER=s3 : configuration manquante (${missing.join(", ")})`);
  return {
    driver,
    localPath,
    s3: {
      endpoint,
      bucket,
      accessKeyId,
      secretAccessKey,
      // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing -- vide ⇒ défaut
      region: env.S3_REGION || "auto",
      forcePathStyle: bool(env.S3_FORCE_PATH_STYLE, true),
    },
  };
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
      // `||` et non `??` (et `eslint-disable` sur les 4 lignes du même type ci-dessous) : une
      // variable présente mais VIDE (cas de .env.example, à remplir en production) doit retomber
      // sur le défaut de dev, pas produire une clé de signature vide — `??` ne le ferait pas.
      // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing
      secret: env.JWT_SECRET || DEV_SECRET,
      // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing
      issuer: env.JWT_ISSUER || "thy-ecosystem",
      accessTtlSec: num(env.ACCESS_TTL_SEC, 15 * 60),
      refreshTtlDays: num(env.REFRESH_TTL_DAYS, 30),
    },
    // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing -- voir plus haut
    hmacPepper: env.HMAC_PEPPER || DEV_SECRET + "-pepper",
    defaultCountry: (env.DEFAULT_COUNTRY ?? "GN").toUpperCase(),
    defaultCurrency: (env.DEFAULT_CURRENCY ?? "GNF").toUpperCase(),
    sms: { driver: "console", ...(env.DEV_FIXED_OTP ? { fixedOtp: env.DEV_FIXED_OTP } : {}) },
    storage: loadStorage(env),
    rateLimitEnabled: bool(env.RATE_LIMIT_ENABLED, true),
    outbox: {
      relayEnabled: bool(env.OUTBOX_RELAY_ENABLED, true),
      pollIntervalMs: num(env.OUTBOX_POLL_INTERVAL_MS, 2000),
    },
    push: { driver: "console" },
    openApiEnabled: bool(env.OPENAPI_ENABLED, nodeEnv !== "production"),
    observability: {
      ...(env.SENTRY_DSN ? { sentryDsn: env.SENTRY_DSN } : {}),
      // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing -- vide ⇒ défaut
      environment: env.SENTRY_ENVIRONMENT || nodeEnv,
      // K_REVISION : révision Cloud Run, posée automatiquement par la plateforme.
      // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing -- vide ⇒ absent
      ...(env.APP_RELEASE || env.K_REVISION ? { release: env.APP_RELEASE || env.K_REVISION } : {}),
    },
    admin: loadAdmin(env, nodeEnv),
  };

  validateConfig(cfg);
  return cfg;
}

export function validateConfig(cfg: AppConfig): void {
  if (cfg.sms.fixedOtp !== undefined && !/^\d{6}$/.test(cfg.sms.fixedOtp))
    throw new Error("DEV_FIXED_OTP doit contenir exactement 6 chiffres");
  if (cfg.env !== "production") return;
  const weak = (s: string) => s.length < 32 || s.includes("dev-only");
  const errors: string[] = [];
  if (weak(cfg.jwt.secret)) errors.push("JWT_SECRET absent/faible (≥ 32 caractères requis)");
  if (weak(cfg.hmacPepper)) errors.push("HMAC_PEPPER absent/faible");
  if (cfg.migratorDatabaseUrl === cfg.databaseUrl)
    errors.push(
      "MIGRATOR_DATABASE_URL doit être distinct de DATABASE_URL (rôles séparés, voir ADR-004)",
    );
  if (cfg.sms.fixedOtp !== undefined)
    errors.push("DEV_FIXED_OTP est interdit en production (code OTP prévisible)");
  // Cette comparaison est toujours vraie TANT QUE ce type n'a qu'une seule valeur possible (aucun
  // adaptateur SMS réel) — gardée pour rester le filet de sécurité qu'elle redeviendra dès qu'un
  // second adaptateur (ADR-005) existera.
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
  if (cfg.sms.driver === "console")
    errors.push('SMS_DRIVER ne peut pas être "console" en production');
  if (cfg.storage.driver === "local")
    errors.push(
      "Le stockage sur disque local est interdit en production (adaptateur S3/GCS requis, ADR-012)",
    );
  // Même logique que ci-dessus : tautologie tant qu'il n'existe qu'un adaptateur push.
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
  if (cfg.push.driver === "console")
    errors.push(
      'Le push "console" (aucune livraison réelle) est interdit en production (FCM requis)',
    );
  if (cfg.storage.s3 && !cfg.storage.s3.endpoint.startsWith("https://"))
    errors.push("S3_ENDPOINT doit être en https en production");
  if (cfg.admin.totpKey.equals(Buffer.from(DEV_TOTP_KEY, "base64")))
    errors.push("ADMIN_TOTP_KEY absent : la clé de développement est interdite en production");
  if (
    cfg.admin.databaseUrl === cfg.databaseUrl ||
    cfg.admin.databaseUrl === cfg.migratorDatabaseUrl
  )
    errors.push("ADMIN_DATABASE_URL doit utiliser le rôle dédié thy_admin_app (distinct de l'app)");
  if (!cfg.admin.cookieSecure)
    errors.push("ADMIN_COOKIE_SECURE ne peut pas être désactivé en production");
  if (!cfg.rateLimitEnabled)
    errors.push("RATE_LIMIT_ENABLED ne peut pas être désactivé en production");
  if (errors.length)
    throw new Error(`Configuration de production invalide:\n - ${errors.join("\n - ")}`);
}
