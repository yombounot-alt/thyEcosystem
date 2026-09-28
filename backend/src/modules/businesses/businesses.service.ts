import { Inject, Injectable } from "@nestjs/common";
import { AuthService } from "../auth/auth.service.js";
import type { Membership } from "../../kernel/auth/auth-types.js";
import { CONFIG, type AppConfig } from "../../kernel/config/config.js";
import { Db, type Tx } from "../../kernel/db/db.service.js";
import { badRequest, conflict, forbidden, notFound, unprocessable } from "../../kernel/errors.js";
import { AuditService, OutboxService } from "../../kernel/infra.services.js";
import {
  NON_OVERRIDABLE_PERMISSIONS,
  PermissionsService,
} from "../../kernel/auth/permissions.service.js";
import { SubscriptionsService } from "../subscriptions/subscriptions.service.js";
import type {
  ChangeMemberRoleDto,
  CreateBusinessDto,
  InviteMemberDto,
  UpdateBusinessDto,
} from "./dto.js";

interface RoleRow {
  id: string;
}

const INVITATION_TTL_DAYS = 7;

const BUSINESS_COLUMNS = `id, name, business_type AS "businessType", country, currency, timezone, phone, address,
                          created_at AS "createdAt"`;

/** Rôles qu'un ADMIN ne peut ni attribuer ni modifier : seul le propriétaire gère les administrateurs. */
const OWNER_ONLY_ROLES = new Set(["OWNER", "ADMIN"]);

@Injectable()
export class BusinessesService {
  constructor(
    private readonly db: Db,
    private readonly outbox: OutboxService,
    private readonly audit: AuditService,
    private readonly auth: AuthService,
    private readonly permissions: PermissionsService,
    private readonly subscriptions: SubscriptionsService,
    @Inject(CONFIG) private readonly cfg: AppConfig,
  ) {}

  private async roleByCode(code: string): Promise<RoleRow> {
    const role = await this.db.one<RoleRow>(
      `SELECT id FROM core.roles WHERE scope = 'BUSINESS' AND code = $1 AND business_id IS NULL`,
      [code],
    );
    if (!role) throw badRequest("INVALID_ROLE", `Rôle inconnu: ${code}`);
    return role;
  }

  // ─── Entreprise ───

  /** Crée l'entreprise, son propriétaire (l'appelant) et réémet un jeton d'accès sur ce contexte. */
  async create(userId: string, dto: CreateBusinessDto) {
    const owner = await this.roleByCode("OWNER");
    // withTenant({ userId }) : pose app.user_id pour que la politique RLS de core.businesses
    // (WITH CHECK owner_id = app.user_id) autorise l'insertion — voir migration 0001.
    const business = await this.db.withTenant({ userId }, async (tx) => {
      const inserted = await tx.query<{
        id: string;
        name: string;
        businessType: string | null;
        country: string;
        currency: string;
        timezone: string;
        phone: string | null;
        address: string | null;
        createdAt: Date;
      }>(
        `INSERT INTO core.businesses (name, business_type, country, currency, timezone, phone, address, owner_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING ${BUSINESS_COLUMNS}`,
        [
          dto.name.trim(),
          dto.businessType ?? null,
          dto.country ?? this.cfg.defaultCountry,
          dto.currency ?? this.cfg.defaultCurrency,
          dto.timezone ?? "Africa/Conakry",
          dto.phone ?? null,
          // `??` ne suffit pas : une adresse blanche ("   ") doit aussi devenir null, pas "".
          // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing
          dto.address?.trim() || null,
          userId,
        ],
      );
      const row = inserted.rows[0];
      if (!row) throw new Error("create: insertion core.businesses sans résultat");
      await tx.query(
        `INSERT INTO core.business_members (business_id, user_id, role_id) VALUES ($1, $2, $3)`,
        [row.id, userId, owner.id],
      );
      await this.subscriptions.startFree(tx, row.id);
      await this.outbox.emit(
        tx,
        "BUSINESS_CREATED",
        "business",
        row.id,
        { businessId: row.id, ownerId: userId },
        row.id,
      );
      await this.audit.log(tx, {
        actorId: userId,
        action: "business.create",
        targetType: "business",
        targetId: row.id,
      });
      return row;
    });
    const session = await this.auth.reissueWithBusiness(userId, business.id);
    return { business, ...session };
  }

  /** Fiche d'une entreprise (le garde a déjà vérifié que l'appelant en est membre). */
  async details(userId: string, businessId: string) {
    const row = await this.db
      .withTenant({ userId }, (tx) =>
        tx.query(`SELECT ${BUSINESS_COLUMNS} FROM core.businesses WHERE id = $1`, [businessId]),
      )
      .then((r) => r.rows[0]);
    if (!row) throw notFound();
    return row;
  }

  async update(businessId: string, actorId: string, dto: UpdateBusinessDto) {
    const sets: string[] = [];
    const params: unknown[] = [businessId];
    const add = (column: string, value: unknown) => {
      params.push(value);
      sets.push(`${column} = $${params.length}`);
    };
    if (dto.name !== undefined) add("name", dto.name.trim());
    if (dto.businessType !== undefined) add("business_type", dto.businessType.trim() || null);
    if (dto.phone !== undefined) add("phone", dto.phone);
    if (dto.address !== undefined) add("address", dto.address.trim() || null);
    return this.db.withTenant({ businessId }, async (tx) => {
      if (sets.length > 0) {
        await tx.query(`UPDATE core.businesses SET ${sets.join(", ")} WHERE id = $1`, params);
        await this.audit.log(tx, {
          actorId,
          action: "business.update",
          targetType: "business",
          targetId: businessId,
          metadata: { fields: Object.keys(dto) },
        });
      }
      const row = await this.db.one(
        `SELECT ${BUSINESS_COLUMNS} FROM core.businesses WHERE id = $1`,
        [businessId],
        tx,
      );
      if (!row) throw notFound();
      return row;
    });
  }

  /** Entreprises dont l'appelant est membre (utile pour un sélecteur, en plus de GET /me/businesses). */
  async listMine(userId: string) {
    return this.db
      .withTenant({ userId }, (tx) =>
        tx.query(
          `SELECT b.id, b.name, b.business_type AS "businessType", b.currency, r.code AS "roleCode"
             FROM core.business_members m
             JOIN core.businesses b ON b.id = m.business_id
             JOIN core.roles r ON r.id = m.role_id
            WHERE m.user_id = $1 AND m.status = 'ACTIVE'
            ORDER BY b.created_at`,
          [userId],
        ),
      )
      .then((r) => r.rows);
  }

  /** Réémet un jeton d'accès sur `businessId` si l'appelant en est membre (sinon 404). */
  activate(userId: string, businessId: string) {
    return this.auth.reissueWithBusiness(userId, businessId);
  }

  // ─── Membres ───

  async listMembers(businessId: string) {
    return this.db
      .withTenant({ businessId }, (tx) =>
        tx.query(
          `SELECT m.id, m.user_id AS "userId", u.full_name AS "fullName", u.phone, r.code AS "roleCode", m.status,
                  m.permission_overrides AS "permissionOverrides", m.created_at AS "createdAt"
             FROM core.business_members m
             JOIN core.users u ON u.id = m.user_id
             JOIN core.roles r ON r.id = m.role_id
            WHERE m.business_id = $1 AND m.status <> 'REMOVED'
            ORDER BY (r.code = 'OWNER') DESC, m.created_at`,
          [businessId],
        ),
      )
      .then((r) => r.rows);
  }

  /**
   * Charge le membre visé et applique les règles communes à toute modification d'un membre :
   * personne ne se modifie soi-même (pas d'auto-promotion), le propriétaire est intouchable, et un
   * ADMIN ne gère pas les autres administrateurs.
   */
  private async targetFor(
    tx: Tx,
    businessId: string,
    actor: Membership,
    actorId: string,
    targetUserId: string,
  ) {
    if (targetUserId === actorId)
      throw forbidden("SELF_MODIFICATION", "Vous ne pouvez pas modifier votre propre accès.");
    const target = await this.db.one<{ roleCode: string; status: string }>(
      `SELECT r.code AS "roleCode", m.status FROM core.business_members m JOIN core.roles r ON r.id = m.role_id
        WHERE m.business_id = $1 AND m.user_id = $2 AND m.status <> 'REMOVED'
        FOR UPDATE OF m`,
      [businessId, targetUserId],
      tx,
    );
    if (!target) throw notFound();
    if (target.roleCode === "OWNER")
      throw conflict(
        "OWNER_IMMUTABLE",
        "Le propriétaire de l'entreprise ne peut pas être modifié.",
      );
    if (actor.roleCode !== "OWNER" && OWNER_ONLY_ROLES.has(target.roleCode))
      throw forbidden("OWNER_ONLY", "Seul le propriétaire peut gérer un administrateur.");
    return target;
  }

  async changeMemberRole(
    businessId: string,
    actor: Membership,
    actorId: string,
    targetUserId: string,
    dto: ChangeMemberRoleDto,
  ) {
    if (actor.roleCode !== "OWNER" && OWNER_ONLY_ROLES.has(dto.roleCode))
      throw forbidden("OWNER_ONLY", "Seul le propriétaire peut nommer un administrateur.");
    const role = await this.roleByCode(dto.roleCode);
    return this.db.withTenant({ businessId }, async (tx) => {
      const target = await this.targetFor(tx, businessId, actor, actorId, targetUserId);
      await tx.query(
        `UPDATE core.business_members SET role_id = $3 WHERE business_id = $1 AND user_id = $2`,
        [businessId, targetUserId, role.id],
      );
      await this.outbox.emit(
        tx,
        "MEMBER_ROLE_CHANGED",
        "business",
        businessId,
        { businessId, userId: targetUserId, roleCode: dto.roleCode },
        businessId,
      );
      await this.audit.log(tx, {
        actorId,
        action: "member.role_change",
        targetType: "user",
        targetId: targetUserId,
        metadata: { businessId, from: target.roleCode, to: dto.roleCode },
      });
      return { businessId, userId: targetUserId, roleCode: dto.roleCode };
    });
  }

  /**
   * Écarts individuels de permissions d'un membre (« configurables individuellement », cahier des
   * charges THY Business écran 23). Un objet vide revient aux permissions par défaut du rôle.
   * `members:manage`/`subscription:manage` ne sont jamais surchargeables. Effectif immédiatement :
   * les surcharges sont relues en base à chaque requête.
   */
  async setPermissionOverrides(
    businessId: string,
    actor: Membership,
    actorId: string,
    targetUserId: string,
    overrides: Record<string, boolean>,
  ) {
    const known = new Set(await this.permissions.listPermissionCodes());
    for (const [code, value] of Object.entries(overrides)) {
      if (typeof value !== "boolean")
        throw badRequest("INVALID_OVERRIDE", `La valeur de « ${code} » doit être true ou false.`);
      if (!known.has(code)) throw badRequest("UNKNOWN_PERMISSION", `Permission inconnue : ${code}`);
      if ((NON_OVERRIDABLE_PERMISSIONS as readonly string[]).includes(code))
        throw badRequest("PERMISSION_NOT_OVERRIDABLE", `« ${code} » ne peut pas être surchargée.`);
    }
    return this.db.withTenant({ businessId }, async (tx) => {
      await this.targetFor(tx, businessId, actor, actorId, targetUserId);
      const value = Object.keys(overrides).length > 0 ? JSON.stringify(overrides) : null;
      await tx.query(
        `UPDATE core.business_members SET permission_overrides = $3::jsonb WHERE business_id = $1 AND user_id = $2`,
        [businessId, targetUserId, value],
      );
      await this.outbox.emit(
        tx,
        "MEMBER_PERMISSIONS_CHANGED",
        "business",
        businessId,
        { businessId, userId: targetUserId },
        businessId,
      );
      await this.audit.log(tx, {
        actorId,
        action: "member.permissions_change",
        targetType: "user",
        targetId: targetUserId,
        metadata: { businessId, overrides },
      });
      return { businessId, userId: targetUserId, overrides };
    });
  }

  /** Suspendre (accès coupé, réversible) ou réactiver un membre. */
  async setMemberStatus(
    businessId: string,
    actor: Membership,
    actorId: string,
    targetUserId: string,
    status: "ACTIVE" | "SUSPENDED",
  ) {
    return this.db.withTenant({ businessId }, async (tx) => {
      const target = await this.targetFor(tx, businessId, actor, actorId, targetUserId);
      if (target.status !== status) {
        await tx.query(
          `UPDATE core.business_members SET status = $3 WHERE business_id = $1 AND user_id = $2`,
          [businessId, targetUserId, status],
        );
        await this.audit.log(tx, {
          actorId,
          action: status === "SUSPENDED" ? "member.suspend" : "member.reactivate",
          targetType: "user",
          targetId: targetUserId,
          metadata: { businessId },
        });
      }
      return { businessId, userId: targetUserId, status };
    });
  }

  /**
   * Retire un membre : son accès cesse à la requête suivante (l'adhésion est relue à chaque appel).
   * La ligne reste (statut REMOVED) pour que ses ventes passées restent attribuables.
   */
  async removeMember(businessId: string, actor: Membership, actorId: string, targetUserId: string) {
    await this.db.withTenant({ businessId }, async (tx) => {
      const target = await this.targetFor(tx, businessId, actor, actorId, targetUserId);
      await tx.query(
        `UPDATE core.business_members SET status = 'REMOVED', permission_overrides = NULL
          WHERE business_id = $1 AND user_id = $2`,
        [businessId, targetUserId],
      );
      await this.outbox.emit(
        tx,
        "MEMBER_REMOVED",
        "business",
        businessId,
        { businessId, userId: targetUserId },
        businessId,
      );
      await this.audit.log(tx, {
        actorId,
        action: "member.remove",
        targetType: "user",
        targetId: targetUserId,
        metadata: { businessId, roleCode: target.roleCode },
      });
    });
  }

  // ─── Invitations (côté entreprise) ───

  /**
   * Invite un numéro. Aucun secret n'est transmis : la personne invitée se connecte par OTP avec CE
   * numéro et trouve l'invitation dans l'app (GET /me/invitations). Réinviter le même numéro
   * remplace l'invitation en attente. Un SMS l'avertit (consommateur d'outbox dédié).
   */
  async invite(businessId: string, actor: Membership, invitedBy: string, dto: InviteMemberDto) {
    if (actor.roleCode !== "OWNER" && OWNER_ONLY_ROLES.has(dto.roleCode))
      throw forbidden("OWNER_ONLY", "Seul le propriétaire peut inviter un administrateur.");
    const role = await this.roleByCode(dto.roleCode);
    const memberLimit = await this.subscriptions.limit(businessId, "members.max");
    return this.db.withTenant({ businessId }, async (tx) => {
      const already = await this.db.one(
        `SELECT 1 FROM core.business_members m JOIN core.users u ON u.id = m.user_id
          WHERE m.business_id = $1 AND u.phone = $2 AND m.status <> 'REMOVED'`,
        [businessId, dto.phone],
        tx,
      );
      if (already) throw conflict("ALREADY_MEMBER", "Ce numéro fait déjà partie de l'équipe.");
      // Places d'équipe : membres + invitations en attente (réinviter le même numéro ne compte pas double).
      const seats = await this.db.one<{ n: number }>(
        `SELECT (SELECT count(*)::int FROM core.business_members
                  WHERE business_id = $1 AND status <> 'REMOVED')
              + (SELECT count(*)::int FROM core.business_invitations
                  WHERE business_id = $1 AND status = 'PENDING' AND expires_at > now() AND phone <> $2) AS n`,
        [businessId, dto.phone],
        tx,
      );
      this.subscriptions.assertRoomFor("members.max", memberLimit, seats?.n ?? 0);
      await tx.query(
        `UPDATE core.business_invitations SET status = 'REVOKED', responded_at = now()
          WHERE business_id = $1 AND phone = $2 AND status = 'PENDING'`,
        [businessId, dto.phone],
      );
      const row = await this.db.one<{
        id: string;
        phone: string;
        status: string;
        expiresAt: Date;
        createdAt: Date;
      }>(
        `INSERT INTO core.business_invitations (business_id, phone, role_id, created_by, expires_at)
         VALUES ($1, $2, $3, $4, now() + make_interval(days => $5))
         RETURNING id, phone, status, expires_at AS "expiresAt", created_at AS "createdAt"`,
        [businessId, dto.phone, role.id, invitedBy, INVITATION_TTL_DAYS],
        tx,
      );
      if (!row) throw new Error("invite: insertion core.business_invitations sans résultat");
      await this.outbox.emit(
        tx,
        "BUSINESS_INVITATION_CREATED",
        "business",
        businessId,
        { businessId, invitationId: row.id },
        businessId,
      );
      await this.audit.log(tx, {
        actorId: invitedBy,
        action: "invitation.create",
        targetType: "invitation",
        targetId: row.id,
        metadata: { businessId, roleCode: dto.roleCode },
      });
      return { ...row, roleCode: dto.roleCode };
    });
  }

  /** Invitations en attente (non expirées) de l'entreprise. */
  async listInvitations(businessId: string) {
    return this.db
      .withTenant({ businessId }, (tx) =>
        tx.query(
          `SELECT i.id, i.phone, r.code AS "roleCode", i.status, i.expires_at AS "expiresAt",
                  i.created_at AS "createdAt", u.full_name AS "invitedByName"
             FROM core.business_invitations i
             JOIN core.roles r ON r.id = i.role_id
             JOIN core.users u ON u.id = i.created_by
            WHERE i.business_id = $1 AND i.status = 'PENDING' AND i.expires_at > now()
            ORDER BY i.created_at DESC`,
          [businessId],
        ),
      )
      .then((r) => r.rows);
  }

  async revokeInvitation(businessId: string, actorId: string, invitationId: string) {
    await this.db.withTenant({ businessId }, async (tx) => {
      const r = await tx.query(
        `UPDATE core.business_invitations SET status = 'REVOKED', responded_at = now()
          WHERE id = $1 AND business_id = $2 AND status = 'PENDING'`,
        [invitationId, businessId],
      );
      if (r.rowCount === 0) throw notFound();
      await this.audit.log(tx, {
        actorId,
        action: "invitation.revoke",
        targetType: "invitation",
        targetId: invitationId,
        metadata: { businessId },
      });
    });
  }

  // ─── Invitations (côté personne invitée) ───

  /** Invitations en attente pour le numéro de l'utilisateur connecté (RLS : son numéro seulement). */
  async myInvitations(userId: string) {
    return this.db
      .withTenant({ userId }, (tx) =>
        tx.query(
          `SELECT i.id, i.business_id AS "businessId", b.name AS "businessName", r.code AS "roleCode",
                  i.expires_at AS "expiresAt", i.created_at AS "createdAt", u.full_name AS "invitedByName"
             FROM core.business_invitations i
             JOIN core.businesses b ON b.id = i.business_id
             JOIN core.roles r ON r.id = i.role_id
             JOIN core.users u ON u.id = i.created_by
            WHERE i.phone = core.current_user_phone() AND i.status = 'PENDING' AND i.expires_at > now()
            ORDER BY i.created_at DESC`,
        ),
      )
      .then((r) => r.rows);
  }

  private async pendingInvitationFor(tx: Tx, invitationId: string) {
    // RLS : seule une invitation adressée au numéro de l'appelant est visible ; sinon 404.
    const inv = await this.db.one<{
      id: string;
      businessId: string;
      roleId: string;
      roleCode: string;
      status: string;
      expiresAt: Date;
    }>(
      `SELECT i.id, i.business_id AS "businessId", i.role_id AS "roleId", r.code AS "roleCode",
              i.status, i.expires_at AS "expiresAt"
         FROM core.business_invitations i JOIN core.roles r ON r.id = i.role_id
        WHERE i.id = $1 AND i.phone = core.current_user_phone()
        FOR UPDATE OF i`,
      [invitationId],
      tx,
    );
    if (!inv) throw notFound();
    if (inv.status !== "PENDING")
      throw unprocessable("INVITATION_INVALID", "Cette invitation n'est plus valable.");
    if (inv.expiresAt < new Date())
      throw unprocessable("INVITATION_EXPIRED", "Cette invitation a expiré.");
    return inv;
  }

  async acceptInvitation(userId: string, invitationId: string) {
    return this.db.withTenant({ userId }, async (tx) => {
      const inv = await this.pendingInvitationFor(tx, invitationId);
      // L'offre a pu baisser depuis l'invitation : les membres déjà présents doivent laisser une place.
      const limit = await this.subscriptions.limit(inv.businessId, "members.max");
      if (limit !== null) {
        const seats = await this.subscriptions.teamSeats(inv.businessId);
        // `seats` compte déjà cette invitation en attente : accepter ne fait que la convertir.
        this.subscriptions.assertRoomFor("members.max", limit, seats - 1);
      }
      // Réintégration d'un ancien membre (REMOVED) : même ligne, nouveau rôle, surcharges effacées.
      await tx.query(
        `INSERT INTO core.business_members (business_id, user_id, role_id) VALUES ($1, $2, $3)
           ON CONFLICT (business_id, user_id)
           DO UPDATE SET role_id = EXCLUDED.role_id, status = 'ACTIVE', permission_overrides = NULL`,
        [inv.businessId, userId, inv.roleId],
      );
      await tx.query(
        `UPDATE core.business_invitations SET status = 'ACCEPTED', accepted_at = now(), responded_at = now()
          WHERE id = $1`,
        [inv.id],
      );
      await this.outbox.emit(
        tx,
        "BUSINESS_MEMBER_ADDED",
        "business",
        inv.businessId,
        { businessId: inv.businessId, userId },
        inv.businessId,
      );
      await this.audit.log(tx, {
        actorId: userId,
        action: "invitation.accept",
        targetType: "invitation",
        targetId: inv.id,
        metadata: { businessId: inv.businessId, roleCode: inv.roleCode },
      });
      return { businessId: inv.businessId, roleCode: inv.roleCode };
    });
  }

  async declineInvitation(userId: string, invitationId: string) {
    await this.db.withTenant({ userId }, async (tx) => {
      const inv = await this.pendingInvitationFor(tx, invitationId);
      await tx.query(
        `UPDATE core.business_invitations SET status = 'DECLINED', responded_at = now() WHERE id = $1`,
        [inv.id],
      );
      await this.audit.log(tx, {
        actorId: userId,
        action: "invitation.decline",
        targetType: "invitation",
        targetId: inv.id,
        metadata: { businessId: inv.businessId },
      });
    });
  }
}
