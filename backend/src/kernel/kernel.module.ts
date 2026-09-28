import { Global, Module } from "@nestjs/common";
import { APP_FILTER, APP_GUARD } from "@nestjs/core";
import { CONFIG, loadConfig } from "./config/config.js";
import { AccessGuard, AuthGuard, RateLimitGuard } from "./auth/guards.js";
import { PermissionsService } from "./auth/permissions.service.js";
import { TokenService } from "./auth/token.service.js";
import { UserStateService } from "./auth/user-state.service.js";
import { Db } from "./db/db.service.js";
import { OutboxHandlerRegistry } from "./events/outbox-handler.js";
import { OutboxRelayService } from "./events/outbox-relay.service.js";
import { AllExceptionsFilter } from "./filters/all-exceptions.filter.js";
import { AuditService, IdempotencyService, OutboxService } from "./infra.services.js";
import { AppLogger } from "./logger.js";
import { NotificationsModule } from "./notifications/notifications.module.js";
import { ObservabilityModule } from "./observability/observability.module.js";
import { StorageModule } from "./storage/storage.module.js";
import { RedisService } from "./redis/redis.service.js";
import { CryptoService } from "./security/crypto.service.js";

/**
 * Socle global du kernel : configuration, accès données, sécurité transverse.
 * Référence : docs/blueprint/02-architecture.md §5 (tiers 1) et §5.2 (pipeline de requête).
 * L'ordre des APP_GUARD est significatif : auth → débit → accès (refus par défaut).
 */
@Global()
@Module({
  imports: [NotificationsModule, StorageModule, ObservabilityModule],
  providers: [
    { provide: CONFIG, useFactory: () => loadConfig() },
    Db,
    RedisService,
    CryptoService,
    TokenService,
    UserStateService,
    PermissionsService,
    AuditService,
    OutboxService,
    IdempotencyService,
    OutboxHandlerRegistry,
    OutboxRelayService,
    AppLogger,
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_GUARD, useClass: RateLimitGuard },
    { provide: APP_GUARD, useClass: AccessGuard },
  ],
  exports: [
    CONFIG,
    Db,
    RedisService,
    CryptoService,
    TokenService,
    UserStateService,
    PermissionsService,
    AuditService,
    OutboxService,
    IdempotencyService,
    OutboxHandlerRegistry,
    OutboxRelayService,
    AppLogger,
    NotificationsModule,
    StorageModule,
    ObservabilityModule,
  ],
})
export class KernelModule {}
