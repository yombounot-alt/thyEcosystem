import { Prisma } from "@prisma/client";
import { createHarness, type Harness } from "../harness.js";

/**
 * Le schéma `biz` est créé par les migrations SQL (backend/migrations), jamais par `prisma migrate`.
 * Prisma n'est qu'un client de requêtes : si `prisma/schema.prisma` s'écarte de la base réelle, les
 * requêtes échouent à l'exécution. Ce test rend l'écart visible immédiatement.
 */
describe("Prisma ↔ migrations SQL : pas de dérive du schéma biz (e2e)", () => {
  let h: Harness;
  beforeAll(async () => {
    h = await createHarness();
  });
  afterAll(async () => {
    await h.close();
  });

  const models = Prisma.dmmf.datamodel.models;

  /** Types PostgreSQL acceptables pour chaque type scalaire Prisma. */
  const COMPATIBLE: Record<string, string[]> = {
    String: ["text", "varchar", "uuid", "bpchar"],
    Int: ["int4", "int2"],
    BigInt: ["int8"],
    Decimal: ["numeric"],
    Float: ["float8", "float4", "numeric"],
    DateTime: ["timestamp", "timestamptz", "date"],
    Boolean: ["bool"],
    Json: ["jsonb", "json"],
    Bytes: ["bytea"],
  };

  it("chaque modèle Prisma a sa table, avec toutes ses colonnes et le bon type de base", async () => {
    const cols = await h.sql.query(
      `SELECT table_name, column_name, data_type, udt_name, is_nullable
         FROM information_schema.columns WHERE table_schema = 'biz'`,
    );
    const byTable = new Map<string, Map<string, { udt: string; nullable: boolean }>>();
    for (const c of cols.rows) {
      if (!byTable.has(c.table_name)) byTable.set(c.table_name, new Map());
      byTable
        .get(c.table_name)!
        .set(c.column_name, { udt: c.udt_name, nullable: c.is_nullable === "YES" });
    }

    const problems: string[] = [];
    for (const model of models) {
      const table = model.dbName ?? model.name;
      const dbCols = byTable.get(table);
      if (!dbCols) {
        problems.push(`table biz.${table} absente (modèle ${model.name})`);
        continue;
      }
      for (const field of model.fields) {
        if (field.kind === "object") continue; // relation Prisma : pas de colonne
        const column = field.dbName ?? field.name;
        const db = dbCols.get(column);
        if (!db) {
          problems.push(`colonne biz.${table}.${column} absente`);
          continue;
        }
        const accepted = field.kind === "enum" ? ["text", "varchar"] : COMPATIBLE[field.type];
        if (accepted && !accepted.includes(db.udt))
          problems.push(
            `biz.${table}.${column} : type ${db.udt} incompatible avec Prisma ${field.type}`,
          );
        if (field.isRequired !== !db.nullable)
          problems.push(
            `biz.${table}.${column} : nullable incohérent (Prisma requis=${field.isRequired}, base nullable=${db.nullable})`,
          );
      }
    }
    expect(problems).toEqual([]);
  });

  it("chaque table du schéma biz est décrite par un modèle Prisma", async () => {
    const tables = await h.sql.query(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'biz' AND table_type = 'BASE TABLE'",
    );
    const known = new Set(models.map((m) => m.dbName ?? m.name));
    const orphans = tables.rows.map((r) => r.table_name as string).filter((t) => !known.has(t));
    expect(orphans).toEqual([]);
  });
});
