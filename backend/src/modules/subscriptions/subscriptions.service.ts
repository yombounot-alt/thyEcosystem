import { Injectable } from "@nestjs/common";
import { Db, type Tx } from "../../kernel/db/db.service.js";
import { forbidden } from "../../kernel/errors.js";

export type EntitlementValues = Record<string, number | null>;

/** Un abonnement dans l'un de ces états retombe sur les droits du plan gratuit (sans perte de données). */
const DEGRADED_STATUSES = new Set(["EXPIRED", "CANCELED"]);
const FALLBACK_PLAN = "FREE";

const LIMIT_MESSAGES: Record<string, (limit: number) => string> = {
  "members.max": (n) =>
    `Votre offre permet ${n} membres dans l'équipe (invitations en attente comprises).`,
  "products.max": (n) => `Votre offre permet ${n} produits actifs au catalogue.`,
  "locations.max": (n) => `Votre offre permet ${n} point(s) de vente.`,
};

/**
 * Moteur d'abonnements et de droits commerciaux (docs/blueprint/04-identity-access.md §6) :
 * la SEULE porte d'entrée pour savoir ce qu'une entreprise a le droit de faire selon son offre.
 * Le serveur applique ; l'app ne fait qu'afficher (GET /businesses/:id/subscription).
 */
@Injectable()
export class SubscriptionsService {
  constructor(private readonly db: Db) {}

  /** Plan gratuit à la création d'une entreprise (dans la transaction qui la crée). */
  async startFree(tx: Tx, businessId: string): Promise<void> {
    await tx.query("SELECT set_config('app.business_id', $1, true)", [businessId]);
    await tx.query(
      `INSERT INTO sub.subscriptions (business_id, plan_code) VALUES ($1, $2)
       ON CONFLICT (business_id) DO NOTHING`,
      [businessId, FALLBACK_PLAN],
    );
    await tx.query(
      `INSERT INTO sub.subscription_events (business_id, type, to_plan) VALUES ($1, 'STARTED', $2)`,
      [businessId, FALLBACK_PLAN],
    );
  }

  private async current(tx: Tx, businessId: string) {
    // Filet de sécurité : une entreprise sans abonnement (créée avant ce moteur) reçoit le gratuit.
    await tx.query(
      `INSERT INTO sub.subscriptions (business_id, plan_code) VALUES ($1, $2)
       ON CONFLICT (business_id) DO NOTHING`,
      [businessId, FALLBACK_PLAN],
    );
    const sub = await this.db.one<{
      planCode: string;
      planName: string;
      status: string;
      currentPeriodEnd: Date | null;
    }>(
      `SELECT s.plan_code, p.name AS plan_name, s.status, s.current_period_end
         FROM sub.subscriptions s JOIN sub.plans p ON p.code = s.plan_code
        WHERE s.business_id = $1`,
      [businessId],
      tx,
    );
    if (!sub) throw new Error(`Abonnement introuvable pour ${businessId}`);
    return sub;
  }

  private async values(tx: Tx, businessId: string, planCode: string): Promise<EntitlementValues> {
    const rows = await tx.query<{ code: string; value: number | null }>(
      `SELECT e.code,
              CASE WHEN o.entitlement_code IS NOT NULL THEN o.value ELSE pe.value END AS value
         FROM sub.entitlements e
         LEFT JOIN sub.plan_entitlements pe ON pe.entitlement_code = e.code AND pe.plan_code = $2
         LEFT JOIN sub.entitlement_overrides o
                ON o.entitlement_code = e.code AND o.business_id = $1
               AND (o.expires_at IS NULL OR o.expires_at > now())`,
      [businessId, planCode],
    );
    return Object.fromEntries(rows.rows.map((r) => [r.code, r.value]));
  }

  /** Droits effectifs de l'entreprise : plan (ou gratuit si expiré) + dérogations en cours. */
  async entitlements(businessId: string): Promise<EntitlementValues> {
    return this.db.withTenant({ businessId }, async (tx) => {
      const sub = await this.current(tx, businessId);
      const plan = DEGRADED_STATUSES.has(sub.status) ? FALLBACK_PLAN : sub.planCode;
      return this.values(tx, businessId, plan);
    });
  }

  /** Maximum autorisé pour une limite (`null` = illimité). */
  async limit(businessId: string, code: string): Promise<number | null> {
    const value = (await this.entitlements(businessId))[code];
    return value ?? null;
  }

  /**
   * Refuse (403 ENTITLEMENT_LIMIT_REACHED) si en ajouter UN de plus dépasserait la limite.
   * `current` est compté par l'appelant, au plus près de l'écriture.
   */
  assertRoomFor(code: string, limit: number | null, current: number): void {
    if (limit === null || current < limit) return;
    const message = LIMIT_MESSAGES[code]?.(limit) ?? `Limite de votre offre atteinte (${code}).`;
    throw forbidden(
      "ENTITLEMENT_LIMIT_REACHED",
      `${message} Passez à l'offre supérieure pour aller plus loin.`,
      { entitlement: code, limit },
    );
  }

  /** Occupation actuelle des limites suivies (pour l'affichage « 2 / 3 membres »). */
  private async usage(tx: Tx, businessId: string) {
    const row = await this.db.one<{ members: number; products: number }>(
      `SELECT (SELECT count(*)::int FROM core.business_members
                WHERE business_id = $1 AND status <> 'REMOVED')
            + (SELECT count(*)::int FROM core.business_invitations
                WHERE business_id = $1 AND status = 'PENDING' AND expires_at > now()) AS members,
              (SELECT count(*)::int FROM biz.products WHERE business_id = $1 AND is_active) AS products`,
      [businessId],
      tx,
    );
    return { "members.max": row?.members ?? 0, "products.max": row?.products ?? 0 };
  }

  /** Nombre de places d'équipe occupées (membres non retirés + invitations en attente). */
  async teamSeats(businessId: string): Promise<number> {
    return this.db.withTenant(
      { businessId },
      async (tx) => (await this.usage(tx, businessId))["members.max"],
    );
  }

  async summary(businessId: string) {
    return this.db.withTenant({ businessId }, async (tx) => {
      const sub = await this.current(tx, businessId);
      const degraded = DEGRADED_STATUSES.has(sub.status);
      const entitlements = await this.values(
        tx,
        businessId,
        degraded ? FALLBACK_PLAN : sub.planCode,
      );
      return {
        plan: { code: sub.planCode, name: sub.planName },
        status: sub.status,
        currentPeriodEnd: sub.currentPeriodEnd,
        entitlements,
        usage: await this.usage(tx, businessId),
      };
    });
  }
}
