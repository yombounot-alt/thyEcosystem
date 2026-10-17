import { loadConfig, requireMigratorUrl } from "../kernel/config/config.js";
import { startupMigrationUrl } from "./migrate.js";

const MIGRATOR = "postgres://thy_migrator:pw@db:5432/thy";

describe("migrations au démarrage de l'API", () => {
  it("hors production, avec MIGRATOR_DATABASE_URL (poste de dev) : migre au démarrage", () => {
    const cfg = loadConfig({ NODE_ENV: "development", MIGRATOR_DATABASE_URL: MIGRATOR });
    expect(startupMigrationUrl(cfg)).toBe(MIGRATOR);
  });

  it("hors production, sans la variable (staging) : ne migre pas, aucune connexion devinée", () => {
    const cfg = loadConfig({ NODE_ENV: "development" });
    expect(cfg.migratorDatabaseUrl).toBeNull();
    expect(startupMigrationUrl(cfg)).toBeNull();
  });

  it("en production, sans MIGRATOR_DATABASE_URL : ne migre pas (le job migrate s'en charge)", () => {
    expect(startupMigrationUrl({ env: "production", migratorDatabaseUrl: null })).toBeNull();
  });

  it("en production, refuse que l'API détienne la connexion du migrateur (elle contourne la RLS)", () => {
    expect(() => startupMigrationUrl({ env: "production", migratorDatabaseUrl: MIGRATOR })).toThrow(
      /job migrate/,
    );
  });
});

describe("connexion du migrateur pour les CLI", () => {
  it("absente par défaut, et exigée avec un message clair", () => {
    const cfg = loadConfig({ NODE_ENV: "development" });
    expect(() => requireMigratorUrl(cfg)).toThrow(/MIGRATOR_DATABASE_URL est requis/);
  });

  it("transmise telle quelle quand elle est fournie", () => {
    const cfg = loadConfig({ NODE_ENV: "development", MIGRATOR_DATABASE_URL: MIGRATOR });
    expect(requireMigratorUrl(cfg)).toBe(MIGRATOR);
  });
});
