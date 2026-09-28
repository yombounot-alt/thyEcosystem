import { Module } from "@nestjs/common";
import { HealthController } from "./health/health.controller.js";
import { KernelModule } from "./kernel/kernel.module.js";
import { AuthModule } from "./modules/auth/auth.module.js";
import { BusinessesModule } from "./modules/businesses/businesses.module.js";
import { UsersModule } from "./modules/users/users.module.js";
import { BusinessModule } from "./modules/business/business.module.js";
import { SubscriptionsModule } from "./modules/subscriptions/subscriptions.module.js";
import { NotificationsEngineModule } from "./modules/notifications/notifications.module.js";

@Module({
  imports: [
    KernelModule,
    AuthModule,
    UsersModule,
    BusinessesModule,
    NotificationsEngineModule,
    SubscriptionsModule,
    BusinessModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
