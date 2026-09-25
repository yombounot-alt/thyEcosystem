import { Injectable } from "@nestjs/common";
import { Db } from "../db/db.service.js";
import { RedisService } from "../redis/redis.service.js";
import type { Membership } from "./auth-types.js";

const ROLE_PERMS_TTL_SEC = 300; // les rôles système ne changent jamais ; les rôles personnalisés (futur) invalideront cette clé

/**
 * Permissions qu'aucune surcharge individuelle ne peut accorder ni retirer : elles appartiennent
 * au rôle (gestion des membres, abonnement). Reprend la règle de thyBusiness (« employees.manage
 * n'est jamais surchargeable »).
 */
export const NON_OVERRIDABLE_PERMISSIONS = ["members:manage", "subscription:manage"] as const;

/**
 * Évaluation RBAC : USER → BUSINESS → ROLE (± surcharges du membre) → PERMISSION
 * (docs/blueprint/04-identity-access.md §4.4). L'adhésion est TOUJOURS relue en base (jamais depuis
 * le seul JWT) — voir AccessGuard.
 */
@Injectable()
export class PermissionsService {
  constructor(
    private readonly db: Db,
    private readonly redis: RedisService,
  ) {}

  /** Adhésion active d'un utilisateur à une entreprise, ou `null` s'il n'en est pas membre. */
  async getMembership(userId: string, businessId: string): Promise<Membership | null> {
    return this.db.withTenant({ userId }, async (tx) => {
      const row = await this.db.one<Membership>(
        `SELECT m.business_id, m.role_id, r.code AS role_code, m.permission_overrides
           FROM core.business_members m
           JOIN core.roles r ON r.id = m.role_id
          WHERE m.business_id = $1 AND m.user_id = $2 AND m.status = 'ACTIVE'`,
        [businessId, userId],
        tx,
      );
      return row;
    });
  }

  private permsKey(roleId: string) {
    return `roleperms:${roleId}`;
  }

  async getRolePermissions(roleId: string): Promise<Set<string>> {
    const cached = await this.redis.getJson<string[]>(this.permsKey(roleId));
    if (cached) return new Set(cached);
    const r = await this.db.query<{ code: string }>(
      `SELECT p.code FROM core.role_permissions rp JOIN core.permissions p ON p.id = rp.permission_id WHERE rp.role_id = $1`,
      [roleId],
    );
    const codes = r.rows.map((row) => row.code);
    await this.redis.setJson(this.permsKey(roleId), codes, ROLE_PERMS_TTL_SEC);
    return new Set(codes);
  }

  /**
   * Permissions effectives d'un membre : celles de son rôle, puis ses écarts individuels
   * (`true` accorde, `false` retire). Les surcharges sont relues avec l'adhésion à chaque requête :
   * un retrait de permission est donc effectif immédiatement.
   */
  async getEffectivePermissions(membership: Membership): Promise<Set<string>> {
    const effective = new Set(await this.getRolePermissions(membership.roleId));
    const overrides = membership.permissionOverrides;
    if (!overrides) return effective;
    for (const [code, allowed] of Object.entries(overrides)) {
      if ((NON_OVERRIDABLE_PERMISSIONS as readonly string[]).includes(code)) continue;
      if (allowed) effective.add(code);
      else effective.delete(code);
    }
    return effective;
  }

  async hasPermission(membership: Membership, code: string): Promise<boolean> {
    return (await this.getEffectivePermissions(membership)).has(code);
  }

  /** Codes valides du catalogue (pour valider des surcharges saisies par un administrateur). */
  async listPermissionCodes(): Promise<string[]> {
    const r = await this.db.query<{ code: string }>(
      "SELECT code FROM core.permissions ORDER BY code",
    );
    return r.rows.map((row) => row.code);
  }

  /** À appeler après tout changement de rôle/permissions d'une entreprise (événement MEMBER_ROLE_CHANGED). */
  async invalidateRole(roleId: string): Promise<void> {
    await this.redis.del(this.permsKey(roleId));
  }
}
