import { Inject, Injectable, OnModuleDestroy } from "@nestjs/common";
import pg from "pg";
import { CONFIG, type AppConfig } from "../config/config.js";

// bigint / numeric / date : conversions explicites (les montants restent < 2^53).
pg.types.setTypeParser(20, (v) => Number(v));
pg.types.setTypeParser(1700, (v) => Number(v));
pg.types.setTypeParser(1082, (v) => v); // date → 'YYYY-MM-DD' (pas de décalage de fuseau)

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Row = Record<string, any>;

export interface QueryResult<T> {
  rows: T[];
  rowCount: number;
}

/** Interface commune au pool et à une transaction : les services acceptent l'un ou l'autre. */
export interface Queryable {
  query<T = Row>(sql: string, params?: unknown[]): Promise<QueryResult<T>>;
}
export type Tx = Queryable;

const camel = (k: string) => k.replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());
function camelizeRow<T>(row: Row): T {
  const out: Row = {};
  for (const k of Object.keys(row)) out[camel(k)] = row[k];
  return out as T;
}

function wrap(runner: {
  query: (sql: string, params?: unknown[]) => Promise<pg.QueryResult>;
}): Queryable {
  return {
    async query<T = Row>(sql: string, params?: unknown[]): Promise<QueryResult<T>> {
      const r = await runner.query(sql, params);
      return { rows: r.rows.map((row) => camelizeRow<T>(row)), rowCount: r.rowCount ?? 0 };
    },
  };
}

/** Contexte de sécurité au niveau ligne (RLS) posé en `SET LOCAL` pour la durée d'une transaction. */
export interface TenantContext {
  /** `core.users.id` de l'appelant — permet à un utilisateur de voir "ses propres" lignes (ex. ses adhésions). */
  userId?: string;
  /** `core.businesses.id` actif — permet de voir les lignes du tenant en cours, vérifié par TenantGuard. */
  businessId?: string;
}

@Injectable()
export class Db implements Queryable, OnModuleDestroy {
  readonly pool: pg.Pool;
  private readonly pooled: Queryable;

  constructor(@Inject(CONFIG) cfg: AppConfig) {
    this.pool = new pg.Pool({
      connectionString: cfg.databaseUrl,
      max: cfg.dbPoolMax,
      statement_timeout: 15_000,
      idle_in_transaction_session_timeout: 30_000,
    });
    this.pool.on("error", () => undefined); // erreurs de connexions inactives : le pool les remplace
    this.pooled = wrap(this.pool);
  }

  query<T = Row>(sql: string, params?: unknown[]): Promise<QueryResult<T>> {
    return this.pooled.query<T>(sql, params);
  }

  async one<T = Row>(sql: string, params?: unknown[], q: Queryable = this): Promise<T | null> {
    const r = await q.query<T>(sql, params);
    return r.rows[0] ?? null;
  }

  /** Transaction : COMMIT si `fn` réussit, ROLLBACK sinon. Toutes les écritures métier passent ici. */
  async tx<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await fn(wrap(client));
      await client.query("COMMIT");
      return result;
    } catch (e) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw e;
    } finally {
      client.release();
    }
  }

  /**
   * Transaction avec contexte tenant posé en RLS (`SET LOCAL app.user_id` / `app.business_id`).
   * Utilisée pour TOUTE lecture ou écriture sur une table protégée par RLS (core.businesses,
   * core.business_members, et plus tard chaque table `biz.*` d'un module métier).
   * Défense en profondeur : même une requête qui oublierait son `WHERE business_id = …` ne peut
   * renvoyer que les lignes autorisées par la politique RLS (jamais une fuite inter-tenant).
   * Référence : docs/blueprint/03-database.md §6, ADR-004.
   */
  async withTenant<T>(ctx: TenantContext, fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.tx(async (tx) => {
      if (ctx.userId)
        await tx.query("SELECT set_config($1, $2, true)", ["app.user_id", ctx.userId]);
      if (ctx.businessId)
        await tx.query("SELECT set_config($1, $2, true)", ["app.business_id", ctx.businessId]);
      return fn(tx);
    });
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}
