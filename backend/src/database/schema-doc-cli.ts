// Génère docs/DATABASE.md depuis le catalogue PostgreSQL d'une base migrée : tables et leurs
// descriptions (COMMENT ON, migration 0011), colonnes, contraintes, index, RLS et politiques,
// droits de chaque rôle applicatif. Le document décrit la base réelle, pas une intention.
//
//   pnpm --filter @thy/backend run db:doc            # régénère le fichier
//   pnpm --filter @thy/backend run db:doc -- --check # échoue si le fichier n'est plus à jour (CI)
//
// Lancé sur le code compilé, avec la connexion du migrateur (lecture du catalogue seulement).
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";
import { loadConfig, requireMigratorUrl } from "../kernel/config/config.js";

const SCHEMAS = ["core", "ops", "ntf", "sub", "biz", "public"];
const APP_ROLES = ["thy_app", "thy_admin_app", "thy_readonly"];
const OUT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../docs/DATABASE.md");

const PRIVILEGES: Record<string, string> = {
  r: "SELECT",
  a: "INSERT",
  w: "UPDATE",
  d: "DELETE",
  D: "TRUNCATE",
  x: "REFERENCES",
  t: "TRIGGER",
};
const COMMANDS: Record<string, string> = {
  r: "SELECT",
  a: "INSERT",
  w: "UPDATE",
  d: "DELETE",
  "*": "ALL",
};

/** Une cellule de tableau Markdown : un `|` non échappé couperait la ligne. */
const cell = (text: string) => text.replace(/\|/g, "\\|").replace(/\n\s*/g, " ");
const code = (text: string) => `\`${cell(text)}\``;

interface Table {
  oid: number;
  schema: string;
  name: string;
  description: string | null;
  rls: boolean;
  forced: boolean;
}

async function generate(client: pg.Client): Promise<string> {
  const q = async <T extends pg.QueryResultRow>(sql: string, params: unknown[] = []) =>
    (await client.query<T>(sql, params)).rows;

  // Objets créés par une extension (PostGIS…) exclus : ils ne relèvent pas de nos migrations.
  const notExtension = `NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.deptype = 'e')`;

  const schemas = await q<{ name: string; description: string | null }>(
    `SELECT nspname AS name, obj_description(oid, 'pg_namespace') AS description
       FROM pg_namespace WHERE nspname = ANY($1) ORDER BY array_position($1, nspname::text)`,
    [SCHEMAS],
  );
  const tables = await q<Table>(
    `SELECT c.oid::int AS oid, n.nspname AS schema, c.relname AS name,
            obj_description(c.oid, 'pg_class') AS description,
            c.relrowsecurity AS rls, c.relforcerowsecurity AS forced
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind IN ('r', 'p') AND n.nspname = ANY($1) AND ${notExtension}
      ORDER BY n.nspname, c.relname`,
    [SCHEMAS],
  );
  const roles = await q<{ name: string; login: boolean; bypassrls: boolean }>(
    `SELECT rolname AS name, rolcanlogin AS login, rolbypassrls AS bypassrls
       FROM pg_roles WHERE rolname LIKE 'thy\\_%' ORDER BY rolname`,
  );
  const migrations = await q<{ name: string }>("SELECT name FROM schema_migrations ORDER BY name");

  const out: string[] = [
    "# Base de données",
    "",
    "> **Fichier généré** par `backend/src/database/schema-doc-cli.ts` depuis le catalogue d'une base",
    "> migrée. Ne pas le modifier à la main : changer les migrations (`backend/migrations/`), puis",
    "> `pnpm --filter @thy/backend run db:doc`. La CI backend échoue s'il n'est plus à jour.",
    "",
    "Conventions et choix : [ADR-003](adr/0003-acces-aux-donnees-et-migrations.md),",
    "[ADR-004](adr/0004-isolation-multi-tenant.md), [ADR-016](adr/0016-identifiants-et-representation-de-l-argent.md),",
    "[ADR-018](adr/0018-decouverte-de-code-existant-strategie-de-consolidation.md) ; cible complète :",
    "[blueprint 03](blueprint/03-database.md).",
    "",
    "## Rôles",
    "",
    "| Rôle | Connexion | Contourne la RLS |",
    "| --- | --- | --- |",
    ...roles.map(
      (r) =>
        `| ${code(r.name)} | ${r.login ? "oui" : "non"} | ${r.bypassrls ? "**oui**" : "non"} |`,
    ),
    "",
    `## Migrations appliquées (${String(migrations.length)})`,
    "",
    ...migrations.map((m) => `- \`${m.name}\``),
    "",
    "## Sommaire",
    "",
  ];

  for (const s of schemas) {
    const inSchema = tables.filter((t) => t.schema === s.name);
    out.push(`- **${s.name}** — ${s.description ?? "_sans description_"}`);
    for (const t of inSchema) out.push(`  - [${t.schema}.${t.name}](#${t.schema}${t.name})`);
  }
  out.push("");

  for (const s of schemas) {
    out.push(`## Schéma \`${s.name}\``, "", s.description ?? "_Sans description._", "");
    for (const t of tables.filter((x) => x.schema === s.name)) {
      out.push(...(await describeTable(q, t)));
    }
  }
  return `${out
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trimEnd()}\n`;
}

async function describeTable(
  q: <T extends pg.QueryResultRow>(sql: string, params?: unknown[]) => Promise<T[]>,
  t: Table,
): Promise<string[]> {
  const out = [`### ${t.schema}.${t.name}`, "", t.description ?? "_Sans description._", ""];
  out.push(
    `RLS : ${t.rls ? (t.forced ? "activée et **forcée**" : "activée, **non forcée**") : "**désactivée**"}`,
    "",
  );

  const columns = await q<{
    name: string;
    type: string;
    notnull: boolean;
    default: string | null;
    description: string | null;
  }>(
    `SELECT a.attname AS name, format_type(a.atttypid, a.atttypmod) AS type, a.attnotnull AS notnull,
            pg_get_expr(d.adbin, d.adrelid) AS default, col_description(a.attrelid, a.attnum) AS description
       FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE a.attrelid = $1 AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum`,
    [t.oid],
  );
  out.push("| Colonne | Type | Nul | Défaut |", "| --- | --- | --- | --- |");
  for (const c of columns) {
    const name = c.description ? `${code(c.name)} — ${cell(c.description)}` : code(c.name);
    out.push(
      `| ${name} | ${code(c.type)} | ${c.notnull ? "non" : "oui"} | ${c.default ? code(c.default) : ""} |`,
    );
  }
  out.push("");

  const constraints = await q<{ name: string; def: string }>(
    `SELECT conname AS name, pg_get_constraintdef(oid) AS def FROM pg_constraint
      WHERE conrelid = $1 ORDER BY contype, conname`,
    [t.oid],
  );
  if (constraints.length) {
    out.push("Contraintes :", "", ...constraints.map((c) => `- \`${c.name}\` : \`${c.def}\``), "");
  }

  const indexes = await q<{ def: string }>(
    `SELECT pg_get_indexdef(i.indexrelid) AS def FROM pg_index i
       JOIN pg_class ic ON ic.oid = i.indexrelid
      WHERE i.indrelid = $1 AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conindid = i.indexrelid)
      ORDER BY ic.relname`,
    [t.oid],
  );
  if (indexes.length) out.push("Index :", "", ...indexes.map((i) => `- \`${i.def}\``), "");

  const policies = await q<{
    name: string;
    cmd: string;
    permissive: boolean;
    roles: string[];
    using: string | null;
    check: string | null;
  }>(
    `SELECT p.polname AS name, p.polcmd AS cmd, p.polpermissive AS permissive,
            ARRAY(SELECT CASE WHEN r = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(r)::text END
                    FROM unnest(p.polroles) AS r ORDER BY 1)::text[] AS roles,
            pg_get_expr(p.polqual, p.polrelid) AS using, pg_get_expr(p.polwithcheck, p.polrelid) AS check
       FROM pg_policy p WHERE p.polrelid = $1 ORDER BY p.polname`,
    [t.oid],
  );
  if (policies.length) {
    out.push("Politiques RLS :", "");
    for (const p of policies) {
      const parts = [`- \`${p.name}\` — ${COMMANDS[p.cmd] ?? p.cmd}, rôles ${p.roles.join(", ")}`];
      if (!p.permissive) parts.push("(restrictive)");
      if (p.using) parts.push(`; USING \`${p.using}\``);
      if (p.check) parts.push(`; WITH CHECK \`${p.check}\``);
      out.push(parts.join(" ").replace(/ ;/g, ";"));
    }
    out.push("");
  } else if (t.rls) {
    out.push("Politiques RLS : aucune (aucune ligne visible pour les rôles soumis à la RLS).", "");
  }

  const grants = await q<{ role: string; privilege: string; columns: string | null }>(
    `SELECT pg_get_userbyid(g.grantee) AS role, g.privilege_type AS privilege, NULL::text AS columns
       FROM pg_class c, aclexplode(c.relacl) g WHERE c.oid = $1 AND pg_get_userbyid(g.grantee) = ANY($2)
     UNION ALL
     SELECT pg_get_userbyid(g.grantee), g.privilege_type, string_agg(a.attname, ', ' ORDER BY a.attnum)
       FROM pg_attribute a, aclexplode(a.attacl) g
      WHERE a.attrelid = $1 AND a.attacl IS NOT NULL AND pg_get_userbyid(g.grantee) = ANY($2)
      GROUP BY 1, 2
      ORDER BY 1, 2`,
    [t.oid, APP_ROLES],
  );
  const order = Object.values(PRIVILEGES);
  out.push("Droits :", "");
  for (const role of APP_ROLES) {
    const mine = grants
      .filter((g) => g.role === role)
      .sort((a, b) => order.indexOf(a.privilege) - order.indexOf(b.privilege))
      .map((g) => (g.columns ? `${g.privilege} (${g.columns})` : g.privilege));
    out.push(`- \`${role}\` : ${mine.length ? mine.join(", ") : "aucun"}`);
  }
  out.push("");
  return out;
}

const cfg = loadConfig();
const client = new pg.Client({ connectionString: requireMigratorUrl(cfg) });
await client.connect();
try {
  const doc = await generate(client);
  if (process.argv.includes("--check")) {
    const current = (() => {
      try {
        return readFileSync(OUT, "utf8").replace(/\r\n/g, "\n");
      } catch {
        return "";
      }
    })();
    if (current !== doc) {
      process.stderr.write(
        "docs/DATABASE.md n'est plus à jour avec les migrations : lancez `pnpm --filter @thy/backend run db:doc` et commitez le résultat.\n",
      );
      process.exitCode = 1;
    } else {
      process.stdout.write("docs/DATABASE.md est à jour.\n");
    }
  } else {
    writeFileSync(OUT, doc);
    process.stdout.write(`Documentation de la base écrite : ${OUT}\n`);
  }
} finally {
  await client.end();
}
