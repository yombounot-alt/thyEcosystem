import { Inject, Injectable, OnModuleDestroy } from "@nestjs/common";
import { Prisma, PrismaClient } from "@prisma/client";
import { CONFIG, type AppConfig } from "../../kernel/config/config.js";

/** Client transactionnel passé aux services : toutes leurs requêtes s'y exécutent sous RLS. */
export type BizTx = Prisma.TransactionClient;

/** Le client Prisma vise le schéma `biz` ; le reste (users, businesses…) est au kernel (schéma `core`). */
function bizUrl(base: string, poolMax: number): string {
  const url = new URL(base);
  url.searchParams.set("schema", "biz");
  url.searchParams.set("connection_limit", String(poolMax));
  return url.toString();
}

/**
 * Accès aux données de THY Business (Prisma reste l'ORM de ce module — ADR-018).
 *
 * Il n'expose volontairement PAS les délégués de modèles (`prisma.product`…) : la seule porte est
 * `run(businessId, fn)`, qui ouvre une transaction et y pose `app.business_id`. Les politiques RLS
 * des tables `biz.*` (migration 0004) font le reste : une requête qui oublierait son
 * `where: { businessId }` ne renverrait aucune ligne d'une autre entreprise (défense en profondeur,
 * ADR-004). Sans contexte, la base répond « aucune ligne » / refuse l'écriture (fail-closed).
 */
@Injectable()
export class BizPrisma implements OnModuleDestroy {
  private readonly client: PrismaClient;

  constructor(@Inject(CONFIG) cfg: AppConfig) {
    this.client = new PrismaClient({
      datasources: { db: { url: bizUrl(cfg.databaseUrl, cfg.dbPoolMax) } },
    });
  }

  /**
   * Exécute `fn` dans UNE transaction cloisonnée sur `businessId` (COMMIT si `fn` réussit, ROLLBACK
   * sinon). `businessId` doit venir d'`AccessGuard` (adhésion vérifiée en base), jamais du client.
   */
  run<T>(businessId: string, fn: (tx: BizTx) => Promise<T>): Promise<T> {
    return this.client.$transaction(
      async (tx) => {
        await tx.$executeRaw`SELECT set_config('app.business_id', ${businessId}, true)`;
        return fn(tx);
      },
      { maxWait: 5_000, timeout: 20_000 },
    );
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.$disconnect();
  }
}

/**
 * Devise et fuseau de l'entreprise, lus dans le kernel (`core.businesses`, visible sous le contexte
 * `app.business_id` posé par `run`). Ces réglages appartiennent à l'entreprise, pas au module.
 */
export async function businessInfo(
  tx: BizTx,
  businessId: string,
): Promise<{ currency: string; timezone: string }> {
  const rows = await tx.$queryRaw<{ currency: string; timezone: string }[]>`
    SELECT currency, timezone FROM core.businesses WHERE id = ${businessId}::uuid`;
  const row = rows[0];
  if (!row) throw new Error(`Entreprise introuvable : ${businessId}`);
  return row;
}
