import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

export const MIGRATIONS_DIR = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../migrations",
);
const LOCK_ID = 727_275_001; // verrou consultatif : une seule instance migre à la fois (distinct de thyServices)

/**
 * Runner de migrations SQL, forward-only (repris tel quel de thyServices — voir
 * docs/plans/consolidation-strategy.md §2 : c'est le migrateur du KERNEL, toutes les tables
 * `core.*` en dépendent, quel que soit l'ORM utilisé par chaque module métier).
 * - chaque fichier est appliqué dans une transaction ;
 * - le checksum SHA-256 est mémorisé : modifier une migration déjà appliquée fait échouer le démarrage.
 */
export async function runMigrations(databaseUrl: string, dir = MIGRATIONS_DIR): Promise<string[]> {
  const client = new pg.Client({ connectionString: databaseUrl });
  await client.connect();
  const applied: string[] = [];
  try {
    await client.query("SELECT pg_advisory_lock($1)", [LOCK_ID]);
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`);
    const done = new Map<string, string>(
      (
        await client.query<{ name: string; checksum: string }>(
          "SELECT name, checksum FROM schema_migrations",
        )
      ).rows.map((r) => [r.name, r.checksum]),
    );
    const files = (await readdir(dir)).filter((f) => f.endsWith(".sql")).sort();
    for (const file of files) {
      const sql = await readFile(path.join(dir, file), "utf8");
      const checksum = createHash("sha256").update(sql).digest("hex");
      const known = done.get(file);
      if (known) {
        if (known !== checksum)
          throw new Error(
            `Migration ${file} modifiée après application (checksum différent). Créez une nouvelle migration.`,
          );
        continue;
      }
      try {
        await client.query("BEGIN");
        await client.query(sql);
        await client.query("INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)", [
          file,
          checksum,
        ]);
        await client.query("COMMIT");
        applied.push(file);
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        throw new Error(`Échec de la migration ${file}: ${(e as Error).message}`);
      }
    }
  } finally {
    await client.query("SELECT pg_advisory_unlock($1)", [LOCK_ID]).catch(() => undefined);
    await client.end();
  }
  return applied;
}
