import { Module } from "@nestjs/common";
import { HealthController } from "./health/health.controller.js";
import { KernelModule } from "./kernel/kernel.module.js";
import { AuthModule } from "./modules/auth/auth.module.js";
import { BusinessesModule } from "./modules/businesses/businesses.module.js";
import { UsersModule } from "./modules/users/users.module.js";

@Module({
  imports: [KernelModule, AuthModule, UsersModule, BusinessesModule],
  controllers: [HealthController],
})
export class AppModule {}
