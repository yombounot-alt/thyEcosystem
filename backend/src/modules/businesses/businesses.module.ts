import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { BusinessesController, InvitationsController } from "./businesses.controller.js";
import { BusinessesService } from "./businesses.service.js";

@Module({
  imports: [AuthModule],
  controllers: [BusinessesController, InvitationsController],
  providers: [BusinessesService],
})
export class BusinessesModule {}
