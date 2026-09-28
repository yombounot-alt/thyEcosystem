import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { SubscriptionsModule } from "../subscriptions/subscriptions.module.js";
import { BusinessesController, MyInvitationsController } from "./businesses.controller.js";
import { BusinessesService } from "./businesses.service.js";
import { InvitationSmsHandler } from "./invitation-sms.handler.js";

@Module({
  imports: [AuthModule, SubscriptionsModule],
  controllers: [BusinessesController, MyInvitationsController],
  providers: [BusinessesService, InvitationSmsHandler],
})
export class BusinessesModule {}
