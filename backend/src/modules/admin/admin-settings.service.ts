import { Injectable } from "@nestjs/common";
import { badRequest, notFound } from "../../kernel/errors.js";
import { AdminDb, auditStaff } from "./admin-db.service.js";
import type { SetOverrideDto, UpsertFlagDto } from "./dto.js";
import type { StaffPrincipal } from "./staff-auth.service.js";

const FLAG_KEY = /^[a-z0-9_.]+$/;

/**
 * Réglages plateforme : feature flags (déploiement) et offre des entreprises (plan, droits,
 * dérogations — ce qui remplaçait jusqu'ici du SQL manuel pour les pilotes). Modifications motivées
 * et auditées ; les dérogations sont aussi tracées dans l'historique d'abonnement.
 */
@Injectable()
export class AdminSettingsService {
  constructor(private readonly db: AdminDb) {}

  async flags() {
    const r = await this.db.query(
      `SELECT key, description, enabled, rollout_percent, countries, updated_at
         FROM ops.feature_flags ORDER BY key`,
    );
    return r.rows;
  }

  async upsertFlag(staff: StaffPrincipal, key: string, dto: UpsertFlagDto) {
    if (!FLAG_KEY.test(key))
      throw badRequest("INVALID_FLAG_KEY", "Clé de flag : minuscules, chiffres, « . » et « _ »");
    return this.db.tx(async (tx) => {
      const before = await this.db.one(
        "SELECT enabled, rollout_percent, countries FROM ops.feature_flags WHERE key = $1",
        [key],
        tx,
      );
      const row = await this.db.one(
        `INSERT INTO ops.feature_flags (key, description, enabled, rollout_percent, countries, updated_at)
         VALUES ($1, $2, $3, $4, $5, now())
         ON CONFLICT (key) DO UPDATE SET description = EXCLUDED.description, enabled = EXCLUDED.enabled,
           rollout_percent = EXCLUDED.rollout_percent, countries = EXCLUDED.countries, updated_at = now()
         RETURNING key, description, enabled, rollout_percent, countries, updated_at`,
        [key, dto.description, dto.enabled, dto.rolloutPercent, dto.countries ?? null],
        tx,
      );
      await auditStaff(tx, {
        staffId: staff.staffId,
        action: "admin.flag.update",
        targetType: "feature_flag",
        targetId: key,
        metadata: {
          reason: dto.reason,
          before,
          after: {
            enabled: dto.enabled,
            rolloutPercent: dto.rolloutPercent,
            countries: dto.countries ?? null,
          },
        },
      });
      return row;
    });
  }

  async searchBusinesses(q: string | undefined) {
    const term = q?.trim() ?? "";
    const r = await this.db.query(
      `SELECT b.id, b.name, b.country, b.currency, b.status, b.created_at AS "createdAt",
              s.plan_code AS "planCode", s.status AS "subscriptionStatus",
              (SELECT count(*)::int FROM core.business_members m
                WHERE m.business_id = b.id AND m.status <> 'REMOVED') AS "members"
         FROM core.businesses b
         LEFT JOIN sub.subscriptions s ON s.business_id = b.id
        WHERE ($1 = '' OR b.name ILIKE '%' || $1 || '%' OR b.id::text = $1)
        ORDER BY b.created_at DESC LIMIT 30`,
      [term],
    );
    return r.rows;
  }

  /** Offre d'une entreprise : pour chaque droit, la valeur du plan et la dérogation éventuelle. */
  async businessEntitlements(businessId: string) {
    const business = await this.db.one<{
      id: string;
      name: string;
      planCode: string | null;
      status: string | null;
    }>(
      `SELECT b.id, b.name, s.plan_code, s.status FROM core.businesses b
         LEFT JOIN sub.subscriptions s ON s.business_id = b.id WHERE b.id = $1`,
      [businessId],
    );
    if (!business) throw notFound();
    const plan = business.planCode ?? "FREE";
    const rows = await this.db.query(
      `SELECT e.code, e.kind, e.description, pe.value AS "planValue",
              o.value AS "overrideValue", (o.entitlement_code IS NOT NULL) AS "hasOverride",
              o.reason AS "overrideReason", o.expires_at AS "overrideExpiresAt",
              (o.entitlement_code IS NOT NULL AND (o.expires_at IS NULL OR o.expires_at > now())) AS "overrideActive"
         FROM sub.entitlements e
         LEFT JOIN sub.plan_entitlements pe ON pe.entitlement_code = e.code AND pe.plan_code = $2
         LEFT JOIN sub.entitlement_overrides o ON o.entitlement_code = e.code AND o.business_id = $1
        ORDER BY e.code`,
      [businessId, plan],
    );
    return { business: { ...business, planCode: plan }, entitlements: rows.rows };
  }

  async setOverride(staff: StaffPrincipal, businessId: string, code: string, dto: SetOverrideDto) {
    await this.assertEntitlement(code);
    const value = dto.value ?? null;
    if (dto.expiresAt && new Date(dto.expiresAt) <= new Date())
      throw badRequest("EXPIRY_IN_PAST", "La date d'expiration doit être dans le futur");
    await this.db.tx(async (tx) => {
      const exists = await this.db.one(
        "SELECT 1 FROM core.businesses WHERE id = $1",
        [businessId],
        tx,
      );
      if (!exists) throw notFound();
      await tx.query(
        `INSERT INTO sub.entitlement_overrides (business_id, entitlement_code, value, reason, expires_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (business_id, entitlement_code) DO UPDATE
           SET value = EXCLUDED.value, reason = EXCLUDED.reason, expires_at = EXCLUDED.expires_at,
               created_at = now()`,
        [businessId, code, value, dto.reason, dto.expiresAt ?? null],
      );
      await tx.query(
        `INSERT INTO sub.subscription_events (business_id, type, actor_id, metadata)
         VALUES ($1, 'OVERRIDE_SET', $2, $3)`,
        [
          businessId,
          staff.staffId,
          JSON.stringify({ code, value, expiresAt: dto.expiresAt ?? null, reason: dto.reason }),
        ],
      );
      await auditStaff(tx, {
        staffId: staff.staffId,
        action: "admin.entitlement.override",
        targetType: "business",
        targetId: businessId,
        metadata: { code, value, expiresAt: dto.expiresAt ?? null, reason: dto.reason },
      });
    });
    return this.businessEntitlements(businessId);
  }

  async removeOverride(staff: StaffPrincipal, businessId: string, code: string, reason: string) {
    await this.db.tx(async (tx) => {
      const r = await tx.query(
        "DELETE FROM sub.entitlement_overrides WHERE business_id = $1 AND entitlement_code = $2",
        [businessId, code],
      );
      if (r.rowCount === 0) throw notFound("Aucune dérogation pour ce droit");
      await tx.query(
        `INSERT INTO sub.subscription_events (business_id, type, actor_id, metadata)
         VALUES ($1, 'OVERRIDE_REMOVED', $2, $3)`,
        [businessId, staff.staffId, JSON.stringify({ code, reason })],
      );
      await auditStaff(tx, {
        staffId: staff.staffId,
        action: "admin.entitlement.override_removed",
        targetType: "business",
        targetId: businessId,
        metadata: { code, reason },
      });
    });
    return this.businessEntitlements(businessId);
  }

  private async assertEntitlement(code: string) {
    const e = await this.db.one("SELECT 1 FROM sub.entitlements WHERE code = $1", [code]);
    if (!e) throw badRequest("UNKNOWN_ENTITLEMENT", `Droit inconnu : ${code}`);
  }
}
