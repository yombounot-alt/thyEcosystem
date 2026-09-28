import { Module } from "@nestjs/common";
import { NotificationsController } from "./notifications.controller.js";
import { NotificationsEventHandler } from "./notifications.handler.js";
import { NotificationsService } from "./notifications.service.js";

/**
 * Moteur de plateforme « notifications » (docs/blueprint/06-platform-engines.md §2) : consomme les
 * événements de l'outbox, alimente la boîte in-app et le push. Les ports d'envoi (SMS, push) sont
 * fournis par le kernel.
 */
@Module({
  controllers: [NotificationsController],
  providers: [NotificationsService, NotificationsEventHandler],
  exports: [NotificationsService],
})
export class NotificationsEngineModule {}
