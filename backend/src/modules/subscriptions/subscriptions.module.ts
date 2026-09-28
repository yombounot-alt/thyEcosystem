import { Module } from "@nestjs/common";
import { FeatureFlagsService } from "./feature-flags.service.js";
import { SubscriptionsController } from "./subscriptions.controller.js";
import { SubscriptionsService } from "./subscriptions.service.js";

/** Moteur de plateforme « abonnements » + feature flags (docs/blueprint/04-identity-access.md §6). */
@Module({
  controllers: [SubscriptionsController],
  providers: [SubscriptionsService, FeatureFlagsService],
  exports: [SubscriptionsService, FeatureFlagsService],
})
export class SubscriptionsModule {}
