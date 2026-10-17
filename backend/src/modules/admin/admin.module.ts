import { Module } from "@nestjs/common";
import { AdminAuditService } from "./admin-audit.service.js";
import { AdminAuthController } from "./admin-auth.controller.js";
import { AdminDb } from "./admin-db.service.js";
import { AdminSettingsService } from "./admin-settings.service.js";
import { AdminUsersService } from "./admin-users.service.js";
import {
  AdminAuditController,
  AdminSettingsController,
  AdminUsersController,
} from "./admin.controller.js";
import { StaffAuthService } from "./staff-auth.service.js";
import { StaffGuard } from "./staff.guard.js";

/**
 * Console d'administration (L0.11, docs/blueprint/09-admin.md) sous `/admin/v1/*` : comptes staff
 * séparés, double authentification obligatoire, rôle PostgreSQL dédié (`thy_admin_app`).
 */
@Module({
  controllers: [
    AdminAuthController,
    AdminUsersController,
    AdminAuditController,
    AdminSettingsController,
  ],
  providers: [
    AdminDb,
    StaffAuthService,
    StaffGuard,
    AdminUsersService,
    AdminAuditService,
    AdminSettingsService,
  ],
})
export class AdminModule {}
