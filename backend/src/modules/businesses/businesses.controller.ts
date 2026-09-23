import { Body, Controller, Get, HttpCode, Param, Patch, Post, Put } from "@nestjs/common";
import {
  Authenticated,
  RequirePermission,
  RequireVerifiedPhone,
} from "../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../kernel/auth/auth-types.js";
import { CurrentUser } from "../../kernel/auth/current-user.js";
import { BusinessesService } from "./businesses.service.js";
import {
  AcceptInvitationDto,
  ChangeMemberRoleDto,
  CreateBusinessDto,
  InviteMemberDto,
  SetPermissionOverridesDto,
} from "./dto.js";

@Controller("businesses")
export class BusinessesController {
  constructor(private readonly businesses: BusinessesService) {}

  @Post()
  @Authenticated()
  @RequireVerifiedPhone()
  @HttpCode(201)
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateBusinessDto) {
    return this.businesses.create(user.id, dto);
  }

  @Get()
  @Authenticated()
  mine(@CurrentUser() user: AuthUser) {
    return this.businesses.listMine(user.id);
  }

  @Post(":businessId/activate")
  @Authenticated()
  @HttpCode(200)
  activate(@Param("businessId") businessId: string, @CurrentUser() user: AuthUser) {
    return this.businesses.activate(user.id, businessId);
  }

  @Get(":businessId/members")
  @RequirePermission("members:manage")
  members(@Param("businessId") businessId: string) {
    return this.businesses.listMembers(businessId);
  }

  @Post(":businessId/invitations")
  @RequirePermission("members:manage")
  @HttpCode(201)
  invite(
    @Param("businessId") businessId: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: InviteMemberDto,
  ) {
    return this.businesses.invite(businessId, user.id, dto);
  }

  @Patch(":businessId/members/:userId")
  @RequirePermission("members:manage")
  changeRole(
    @Param("businessId") businessId: string,
    @Param("userId") userId: string,
    @Body() dto: ChangeMemberRoleDto,
  ) {
    return this.businesses.changeMemberRole(businessId, userId, dto);
  }

  @Put(":businessId/members/:userId/permissions")
  @RequirePermission("members:manage")
  setPermissions(
    @Param("businessId") businessId: string,
    @Param("userId") userId: string,
    @Body() dto: SetPermissionOverridesDto,
  ) {
    return this.businesses.setPermissionOverrides(businessId, userId, dto.overrides);
  }
}

/** Route hors `/businesses/:id/**` : l'appelant n'est pas encore forcément membre au moment d'accepter. */
@Controller("invitations")
export class InvitationsController {
  constructor(private readonly businesses: BusinessesService) {}

  @Post("accept")
  @Authenticated()
  @RequireVerifiedPhone()
  @HttpCode(200)
  accept(@CurrentUser() user: AuthUser, @Body() dto: AcceptInvitationDto) {
    return this.businesses.accept(user.id, dto);
  }
}
