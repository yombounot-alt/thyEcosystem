import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ApiExcludeController } from "@nestjs/swagger";
import { Public } from "../../kernel/auth/auth-types.js";
import { AdminAuditService } from "./admin-audit.service.js";
import { AdminSettingsService } from "./admin-settings.service.js";
import { AdminUsersService } from "./admin-users.service.js";
import { AuditQuery, ReasonDto, SetOverrideDto, UpsertFlagDto, UserSearchQuery } from "./dto.js";
import type { StaffPrincipal } from "./staff-auth.service.js";
import { AdminPermission, CurrentStaff, StaffGuard } from "./staff.guard.js";

/** Utilisateurs (support) — docs/blueprint/09-admin.md §4 « Users ». */
@ApiExcludeController()
@Public()
@UseGuards(StaffGuard)
@Controller("admin/v1/users")
export class AdminUsersController {
  constructor(private readonly users: AdminUsersService) {}

  @Get()
  @AdminPermission("admin:users.read")
  search(@Query() q: UserSearchQuery) {
    return this.users.search(q.q, q.limit, q.cursor);
  }

  @Get(":id")
  @AdminPermission("admin:users.read")
  detail(@Param("id", ParseUUIDPipe) id: string) {
    return this.users.detail(id);
  }

  @Post(":id/reveal-phone")
  @HttpCode(200)
  @AdminPermission("admin:users.reveal")
  reveal(
    @CurrentStaff() staff: StaffPrincipal,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ReasonDto,
  ) {
    return this.users.revealPhone(staff, id, dto.reason);
  }

  @Post(":id/suspend")
  @HttpCode(200)
  @AdminPermission("admin:users.restrict")
  suspend(
    @CurrentStaff() staff: StaffPrincipal,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ReasonDto,
  ) {
    return this.users.setSuspended(staff, id, true, dto.reason);
  }

  @Post(":id/reactivate")
  @HttpCode(200)
  @AdminPermission("admin:users.restrict")
  reactivate(
    @CurrentStaff() staff: StaffPrincipal,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ReasonDto,
  ) {
    return this.users.setSuspended(staff, id, false, dto.reason);
  }

  @Post(":id/revoke-sessions")
  @HttpCode(200)
  @AdminPermission("admin:users.restrict")
  revoke(
    @CurrentStaff() staff: StaffPrincipal,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ReasonDto,
  ) {
    return this.users.revokeSessions(staff, id, dto.reason);
  }
}

/** Journal d'audit — docs/blueprint/09-admin.md §4 « Audit ». */
@ApiExcludeController()
@Public()
@UseGuards(StaffGuard)
@Controller("admin/v1/audit")
export class AdminAuditController {
  constructor(private readonly audit: AdminAuditService) {}

  @Get()
  @AdminPermission("admin:audit.read")
  search(@Query() q: AuditQuery) {
    return this.audit.search(q);
  }
}

/** Réglages : feature flags et offre des entreprises — §4 « System settings ». */
@ApiExcludeController()
@Public()
@UseGuards(StaffGuard)
@Controller("admin/v1")
export class AdminSettingsController {
  constructor(private readonly settings: AdminSettingsService) {}

  @Get("settings/flags")
  @AdminPermission("admin:settings.manage")
  flags() {
    return this.settings.flags();
  }

  @Put("settings/flags/:key")
  @AdminPermission("admin:settings.manage")
  upsertFlag(
    @CurrentStaff() staff: StaffPrincipal,
    @Param("key") key: string,
    @Body() dto: UpsertFlagDto,
  ) {
    return this.settings.upsertFlag(staff, key, dto);
  }

  @Get("businesses")
  @AdminPermission("admin:businesses.read")
  businesses(@Query("q") q?: string) {
    return this.settings.searchBusinesses(q?.slice(0, 100));
  }

  @Get("businesses/:id/entitlements")
  @AdminPermission("admin:businesses.read")
  entitlements(@Param("id", ParseUUIDPipe) id: string) {
    return this.settings.businessEntitlements(id);
  }

  @Put("businesses/:id/entitlements/:code")
  @AdminPermission("admin:settings.manage")
  setOverride(
    @CurrentStaff() staff: StaffPrincipal,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("code") code: string,
    @Body() dto: SetOverrideDto,
  ) {
    return this.settings.setOverride(staff, id, code, dto);
  }

  @Delete("businesses/:id/entitlements/:code")
  @AdminPermission("admin:settings.manage")
  removeOverride(
    @CurrentStaff() staff: StaffPrincipal,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("code") code: string,
    @Body() dto: ReasonDto,
  ) {
    return this.settings.removeOverride(staff, id, code, dto.reason);
  }
}
