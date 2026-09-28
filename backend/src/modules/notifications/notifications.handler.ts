import { Injectable, type OnModuleInit } from "@nestjs/common";
import { Db } from "../../kernel/db/db.service.js";
import {
  OutboxHandlerRegistry,
  type OutboxEvent,
  type OutboxEventHandler,
} from "../../kernel/events/outbox-handler.js";
import { type NotificationType } from "./notification-types.js";
import { NotificationsService } from "./notifications.service.js";

const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);

/**
 * Traduit les événements métier (outbox) en notifications. Idempotent : chaque notification porte
 * une clé `<événement>:<type>` — un événement rejoué (relais « au moins une fois ») ne crée rien de plus.
 */
@Injectable()
export class NotificationsEventHandler implements OutboxEventHandler, OnModuleInit {
  readonly consumer = "notifications.v1";
  readonly eventTypes = [
    "BUSINESS_CREATED",
    "BUSINESS_MEMBER_ADDED",
    "MEMBER_ROLE_CHANGED",
    "MEMBER_PERMISSIONS_CHANGED",
    "MEMBER_REMOVED",
    "BUSINESS_INVITATION_CREATED",
    "SECURITY_TOKEN_REUSE",
    "STOCK_LOW",
    "STOCK_NEGATIVE",
  ] as const;

  constructor(
    private readonly registry: OutboxHandlerRegistry,
    private readonly notifications: NotificationsService,
    private readonly db: Db,
  ) {}

  onModuleInit(): void {
    this.registry.register(this);
  }

  async handle(event: OutboxEvent): Promise<void> {
    const p = event.payload;
    const businessId = str(p.businessId) ?? event.businessId ?? undefined;
    const send = (userId: string, type: NotificationType, data: Record<string, string>) =>
      this.notifications.notify({
        userId,
        type,
        data,
        businessId: businessId ?? null,
        dedupeKey: `${event.id}:${type}:${userId}`,
      });

    switch (event.eventType) {
      case "BUSINESS_CREATED": {
        const ownerId = str(p.ownerId);
        const biz = businessId && (await this.business(businessId));
        if (ownerId && biz)
          await send(ownerId, "BUSINESS_WELCOME", { businessName: biz.name, businessId: biz.id });
        return;
      }
      case "BUSINESS_MEMBER_ADDED": {
        const userId = str(p.userId);
        if (!userId || !businessId) return;
        const biz = await this.business(businessId);
        const member = await this.member(businessId, userId);
        if (!biz || !member) return;
        await send(userId, "MEMBER_JOINED", {
          businessName: biz.name,
          businessId,
          roleCode: member.roleCode,
        });
        for (const managerId of await this.managers(businessId, userId)) {
          await send(managerId, "TEAM_MEMBER_JOINED", {
            businessName: biz.name,
            businessId,
            memberName: member.fullName ?? "Un nouveau membre",
            roleCode: member.roleCode,
          });
        }
        return;
      }
      case "MEMBER_ROLE_CHANGED":
      case "MEMBER_PERMISSIONS_CHANGED":
      case "MEMBER_REMOVED": {
        const userId = str(p.userId);
        if (!userId || !businessId) return;
        const biz = await this.business(businessId);
        if (!biz) return;
        const roleCode = str(p.roleCode) ?? "";
        await send(userId, event.eventType, {
          businessName: biz.name,
          businessId,
          roleCode,
        });
        return;
      }
      case "BUSINESS_INVITATION_CREATED": {
        const invitationId = str(p.invitationId);
        if (!invitationId || !businessId) return;
        const inv = await this.invitation(businessId, invitationId);
        if (inv?.status !== "PENDING") return;
        const invitee = await this.db.one<{ id: string }>(
          "SELECT id FROM core.users WHERE phone = $1 AND status <> 'DELETED'",
          [inv.phone],
        );
        // Pas encore de compte : l'invitation l'attendra à sa première connexion (GET /me/invitations),
        // et le SMS d'invitation (consommateur séparé) lui dit où la trouver.
        if (!invitee) return;
        await send(invitee.id, "BUSINESS_INVITATION", {
          businessName: inv.businessName,
          businessId,
          invitationId,
          roleCode: inv.roleCode,
        });
        return;
      }
      case "STOCK_LOW":
      case "STOCK_NEGATIVE": {
        if (!businessId) return;
        const data = {
          businessId,
          productId: str(p.productId) ?? "",
          productName: str(p.productName) ?? "",
          stock: str(p.stock) ?? "",
          threshold: str(p.threshold) ?? "",
        };
        for (const userId of await this.holdersOf(businessId, "inventory:adjust"))
          await send(userId, event.eventType, data);
        return;
      }
      case "SECURITY_TOKEN_REUSE": {
        const userId = str(p.userId);
        if (userId) await send(userId, "SECURITY_SESSION_REVOKED", {});
        return;
      }
    }
  }

  private business(businessId: string) {
    return this.db.withTenant({ businessId }, (tx) =>
      this.db.one<{ id: string; name: string }>(
        "SELECT id, name FROM core.businesses WHERE id = $1",
        [businessId],
        tx,
      ),
    );
  }

  private member(businessId: string, userId: string) {
    return this.db.withTenant({ businessId }, (tx) =>
      this.db.one<{ roleCode: string; fullName: string | null }>(
        `SELECT r.code AS "roleCode", u.full_name AS "fullName"
           FROM core.business_members m
           JOIN core.roles r ON r.id = m.role_id
           JOIN core.users u ON u.id = m.user_id
          WHERE m.business_id = $1 AND m.user_id = $2`,
        [businessId, userId],
        tx,
      ),
    );
  }

  /** Propriétaires et administrateurs actifs (hors `exceptUserId`) : ceux qui gèrent l'équipe. */
  private async managers(businessId: string, exceptUserId: string): Promise<string[]> {
    const r = await this.db.withTenant({ businessId }, (tx) =>
      tx.query<{ userId: string }>(
        `SELECT m.user_id FROM core.business_members m JOIN core.roles r ON r.id = m.role_id
          WHERE m.business_id = $1 AND m.status = 'ACTIVE' AND r.code IN ('OWNER', 'ADMIN')
            AND m.user_id <> $2`,
        [businessId, exceptUserId],
      ),
    );
    return r.rows.map((row) => row.userId);
  }

  /**
   * Membres actifs dont le RÔLE ou la surcharge individuelle accorde `permission` (ex. les
   * responsables du stock pour une alerte de stock).
   */
  private async holdersOf(businessId: string, permission: string): Promise<string[]> {
    const r = await this.db.withTenant({ businessId }, (tx) =>
      tx.query<{ userId: string }>(
        `SELECT m.user_id FROM core.business_members m
          WHERE m.business_id = $1 AND m.status = 'ACTIVE'
            AND COALESCE(
                  (m.permission_overrides ->> $2)::boolean,
                  EXISTS (SELECT 1 FROM core.role_permissions rp
                            JOIN core.permissions p ON p.id = rp.permission_id
                           WHERE rp.role_id = m.role_id AND p.code = $2))`,
        [businessId, permission],
      ),
    );
    return r.rows.map((row) => row.userId);
  }

  private invitation(businessId: string, invitationId: string) {
    return this.db.withTenant({ businessId }, (tx) =>
      this.db.one<{ phone: string; status: string; roleCode: string; businessName: string }>(
        `SELECT i.phone, i.status, r.code AS "roleCode", b.name AS "businessName"
           FROM core.business_invitations i
           JOIN core.roles r ON r.id = i.role_id
           JOIN core.businesses b ON b.id = i.business_id
          WHERE i.id = $1 AND i.business_id = $2`,
        [invitationId, businessId],
        tx,
      ),
    );
  }
}
