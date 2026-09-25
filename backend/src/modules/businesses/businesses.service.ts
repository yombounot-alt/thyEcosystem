import { Inject, Injectable } from "@nestjs/common";
import { AuthService } from "../auth/auth.service.js";
import { CONFIG, type AppConfig } from "../../kernel/config/config.js";
import { Db } from "../../kernel/db/db.service.js";
import { badRequest, conflict, forbidden, notFound, unprocessable } from "../../kernel/errors.js";
import { OutboxService } from "../../kernel/infra.services.js";
import { CryptoService } from "../../kernel/security/crypto.service.js";
import {
  NON_OVERRIDABLE_PERMISSIONS,
  PermissionsService,
} from "../../kernel/auth/permissions.service.js";
import type {
  AcceptInvitationDto,
  ChangeMemberRoleDto,
  CreateBusinessDto,
  InviteMemberDto,
} from "./dto.js";

interface RoleRow {
  id: string;
}

@Injectable()
export class BusinessesService {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    private readonly outbox: OutboxService,
    private readonly auth: AuthService,
    private readonly permissions: PermissionsService,
    @Inject(CONFIG) private readonly cfg: AppConfig,
  ) {}

  /**
   * Écarts individuels de permissions d'un membre (« configurables individuellement », cahier des
   * charges THY Business écran 23). Un objet vide revient aux permissions par défaut du rôle. Le
   * propriétaire garde toujours toutes les permissions, et `members:manage`/`subscription:manage`
   * ne sont jamais surchargeables. Effectif immédiatement : les surcharges sont relues en base à
   * chaque requête.
   */
  async setPermissionOverrides(
    businessId: string,
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
      const target = await this.db.one<{ roleCode: string }>(
        `SELECT r.code AS "roleCode" FROM core.business_members m JOIN core.roles r ON r.id = m.role_id
          WHERE m.business_id = $1 AND m.user_id = $2`,
        [businessId, targetUserId],
        tx,
      );
      if (!target) throw notFound();
      if (target.roleCode === "OWNER")
        throw conflict(
          "OWNER_PERMISSIONS_FIXED",
          "Le propriétaire a toujours toutes les permissions.",
        );
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
      return { businessId, userId: targetUserId, overrides };
    });
  }

  private async roleByCode(code: string): Promise<RoleRow> {
    const role = await this.db.one<RoleRow>(
      `SELECT id FROM core.roles WHERE scope = 'BUSINESS' AND code = $1 AND business_id IS NULL`,
      [code],
    );
    if (!role) throw badRequest("INVALID_ROLE", `Rôle inconnu: ${code}`);
    return role;
  }

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
         RETURNING id, name, business_type AS "businessType", country, currency, timezone, phone, address, created_at AS "createdAt"`,
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
      await this.outbox.emit(
        tx,
        "BUSINESS_CREATED",
        "business",
        row.id,
        { businessId: row.id, ownerId: userId },
        row.id,
      );
      return row;
    });
    const session = await this.auth.reissueWithBusiness(userId, business.id);
    return { business, ...session };
  }

  /** Fiche d'une entreprise (le garde a déjà vérifié que l'appelant en est membre). */
  async details(userId: string, businessId: string) {
    const row = await this.db
      .withTenant({ userId }, (tx) =>
        tx.query(
          `SELECT id, name, business_type AS "businessType", country, currency, timezone, phone, address,
                  created_at AS "createdAt"
             FROM core.businesses WHERE id = $1`,
          [businessId],
        ),
      )
      .then((r) => r.rows[0]);
    if (!row) throw notFound();
    return row;
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

  async listMembers(businessId: string) {
    return this.db
      .withTenant({ businessId }, (tx) =>
        tx.query(
          `SELECT m.id, m.user_id AS "userId", u.full_name AS "fullName", u.phone, r.code AS "roleCode", m.status,
                  m.permission_overrides AS "permissionOverrides", m.created_at AS "createdAt"
             FROM core.business_members m
             JOIN core.users u ON u.id = m.user_id
             JOIN core.roles r ON r.id = m.role_id
            WHERE m.business_id = $1
            ORDER BY m.created_at`,
          [businessId],
        ),
      )
      .then((r) => r.rows);
  }

  /**
   * NOTE Phase 0 : le jeton d'invitation est renvoyé en clair dans la réponse HTTP faute d'envoi
   * SMS implémenté (docs/blueprint/06-platform-engines.md §2, module `notifications` complet en
   * Phase 1). Ne JAMAIS journaliser ce jeton ; à retirer de la réponse dès l'envoi SMS branché.
   */
  async invite(businessId: string, invitedBy: string, dto: InviteMemberDto) {
    const role = await this.roleByCode(dto.roleCode);
    const token = this.crypto.randomToken(24);
    const row = await this.db
      .withTenant({ businessId }, (tx) =>
        tx.query<{ id: string; phone: string; expiresAt: Date }>(
          `INSERT INTO core.business_invitations (business_id, phone, role_id, token_hash, created_by, expires_at)
         VALUES ($1, $2, $3, $4, $5, now() + interval '7 days')
         RETURNING id, phone, expires_at AS "expiresAt"`,
          [businessId, dto.phone, role.id, this.crypto.tokenHash(token), invitedBy],
        ),
      )
      .then((r) => {
        const row = r.rows[0];
        if (!row) throw new Error("invite: insertion core.business_invitations sans résultat");
        return row;
      });
    return { ...row, token };
  }

  /**
   * Accepte une invitation : le token identifie l'entreprise et le rôle, mais l'appelant doit
   * être authentifié avec le NUMÉRO invité (sinon quelqu'un d'autre pourrait rejouer un lien reçu
   * par erreur) — docs/blueprint/04-identity-access.md §4.5.
   */
  async accept(userId: string, dto: AcceptInvitationDto) {
    const tokenHash = this.crypto.tokenHash(dto.token);
    // withTenant({ userId }) : pose app.user_id, requis par la politique RLS de
    // core.business_members pour autoriser l'insertion de SA PROPRE adhésion.
    return this.db.withTenant({ userId }, async (tx) => {
      const inv = await this.db.one<{
        id: string;
        businessId: string;
        phone: string;
        roleId: string;
        status: string;
        expiresAt: Date;
      }>(
        `SELECT id, business_id AS "businessId", phone, role_id AS "roleId", status, expires_at AS "expiresAt"
           FROM core.business_invitations WHERE token_hash = $1 FOR UPDATE`,
        [tokenHash],
        tx,
      );
      if (inv?.status !== "PENDING")
        throw unprocessable("INVITATION_INVALID", "Invitation invalide ou déjà utilisée");
      if (inv.expiresAt < new Date())
        throw unprocessable("INVITATION_EXPIRED", "Invitation expirée");
      const user = await this.db.one<{ phone: string }>(
        "SELECT phone FROM core.users WHERE id = $1",
        [userId],
        tx,
      );
      if (user?.phone !== inv.phone)
        throw forbidden(
          "INVITATION_PHONE_MISMATCH",
          "Cette invitation ne correspond pas à votre numéro de téléphone",
        );

      await tx.query(
        `INSERT INTO core.business_members (business_id, user_id, role_id) VALUES ($1, $2, $3)
           ON CONFLICT (business_id, user_id) DO UPDATE SET role_id = EXCLUDED.role_id, status = 'ACTIVE'`,
        [inv.businessId, userId, inv.roleId],
      );
      await tx.query(
        `UPDATE core.business_invitations SET status = 'ACCEPTED', accepted_at = now() WHERE id = $1`,
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
      return { businessId: inv.businessId };
    });
  }

  async changeMemberRole(businessId: string, targetUserId: string, dto: ChangeMemberRoleDto) {
    const role = await this.roleByCode(dto.roleCode);
    return this.db.withTenant({ businessId }, async (tx) => {
      // Le dernier OWNER ne peut jamais être rétrogradé (docs/blueprint/04-identity-access.md §4.2).
      const current = await this.db.one<{ roleCode: string }>(
        `SELECT r.code AS "roleCode" FROM core.business_members m JOIN core.roles r ON r.id = m.role_id
          WHERE m.business_id = $1 AND m.user_id = $2`,
        [businessId, targetUserId],
        tx,
      );
      if (!current) throw notFound();
      if (current.roleCode === "OWNER") {
        const owners = await this.db.one<{ n: number }>(
          `SELECT count(*)::int AS n FROM core.business_members m JOIN core.roles r ON r.id = m.role_id
            WHERE m.business_id = $1 AND r.code = 'OWNER' AND m.status = 'ACTIVE'`,
          [businessId],
          tx,
        );
        if ((owners?.n ?? 0) <= 1)
          throw conflict(
            "LAST_OWNER",
            "Impossible de retirer le dernier propriétaire de l'entreprise",
          );
      }
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
      return { businessId, userId: targetUserId, roleCode: dto.roleCode };
    });
  }
}
