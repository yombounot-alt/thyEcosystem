import { Inject, Injectable, type OnModuleInit } from "@nestjs/common";
import { Db } from "../../kernel/db/db.service.js";
import {
  OutboxHandlerRegistry,
  type OutboxEvent,
  type OutboxEventHandler,
} from "../../kernel/events/outbox-handler.js";
import { SMS_SENDER, type SmsSenderPort } from "../../kernel/notifications/sms-sender.port.js";

/**
 * Prévient la personne invitée par SMS. Consommateur SÉPARÉ des notifications in-app : le relais
 * mémorise chaque consommateur à part (`ops.processed_events`), donc un échec de la boîte in-app
 * ne renvoie pas un second SMS, et inversement.
 *
 * Le SMS ne contient aucun secret : il dit seulement où trouver l'invitation (se connecter à THY
 * avec ce numéro). Une invitation révoquée entre-temps n'est pas envoyée.
 */
@Injectable()
export class InvitationSmsHandler implements OutboxEventHandler, OnModuleInit {
  readonly consumer = "invitation-sms.v1";
  readonly eventTypes = ["BUSINESS_INVITATION_CREATED"] as const;

  constructor(
    private readonly registry: OutboxHandlerRegistry,
    private readonly db: Db,
    @Inject(SMS_SENDER) private readonly sms: SmsSenderPort,
  ) {}

  onModuleInit(): void {
    this.registry.register(this);
  }

  async handle(event: OutboxEvent): Promise<void> {
    const invitationId = event.payload.invitationId;
    const businessId = event.businessId;
    if (typeof invitationId !== "string" || !businessId) return;
    const inv = await this.db.withTenant({ businessId }, (tx) =>
      this.db.one<{ phone: string; status: string; businessName: string }>(
        `SELECT i.phone, i.status, b.name AS "businessName"
           FROM core.business_invitations i JOIN core.businesses b ON b.id = i.business_id
          WHERE i.id = $1`,
        [invitationId],
        tx,
      ),
    );
    if (inv?.status !== "PENDING") return;
    await this.sms.sendText(
      inv.phone,
      `${inv.businessName} vous invite à rejoindre son équipe sur THY. ` +
        `Ouvrez l'application THY et connectez-vous avec ce numéro pour accepter.`,
    );
  }
}
