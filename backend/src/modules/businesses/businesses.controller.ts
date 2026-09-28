import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
} from "@nestjs/common";
import {
  Authenticated,
  RateLimit,
  RequireMembership,
  RequirePermission,
  RequireVerifiedPhone,
} from "../../kernel/auth/auth-types.js";
import type { AuthUser, Membership } from "../../kernel/auth/auth-types.js";
import { CurrentMembership, CurrentUser } from "../../kernel/auth/current-user.js";
import { BusinessesService } from "./businesses.service.js";
import {
  ChangeMemberRoleDto,
  ChangeMemberStatusDto,
  CreateBusinessDto,
  InviteMemberDto,
  SetPermissionOverridesDto,
  UpdateBusinessDto,
} from "./dto.js";

@ApiTags("businesses")
@ApiBearerAuth()
@Controller("businesses")
export class BusinessesController {
  constructor(private readonly businesses: BusinessesService) {}

  @Post()
  @Authenticated()
  @RequireVerifiedPhone()
  @RateLimit({ name: "business-create", limit: 10, windowSec: 3600, by: "user", failClosed: true })
  @HttpCode(201)
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateBusinessDto) {
    return this.businesses.create(user.id, dto);
  }

  @Get()
  @Authenticated()
  mine(@CurrentUser() user: AuthUser) {
    return this.businesses.listMine(user.id);
  }

  /** Fiche de l'entreprise : ouverte à tout membre (la lecture des données métier a ses propres permissions). */
  @Get(":businessId")
  @RequireMembership()
  details(@Param("businessId", ParseUUIDPipe) businessId: string, @CurrentUser() user: AuthUser) {
    return this.businesses.details(user.id, businessId);
  }

  @Patch(":businessId")
  @RequirePermission("business:settings")
  update(
    @Param("businessId", ParseUUIDPipe) businessId: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: UpdateBusinessDto,
  ) {
    return this.businesses.update(businessId, user.id, dto);
  }

  @Post(":businessId/activate")
  @Authenticated()
  @HttpCode(200)
  activate(@Param("businessId", ParseUUIDPipe) businessId: string, @CurrentUser() user: AuthUser) {
    return this.businesses.activate(user.id, businessId);
  }

  // ─── Équipe ───

  @Get(":businessId/members")
  @RequirePermission("members:manage")
  members(@Param("businessId", ParseUUIDPipe) businessId: string) {
    return this.businesses.listMembers(businessId);
  }

  @Patch(":businessId/members/:userId")
  @RequirePermission("members:manage")
  changeRole(
    @Param("businessId", ParseUUIDPipe) businessId: string,
    @Param("userId", ParseUUIDPipe) userId: string,
    @CurrentUser() user: AuthUser,
    @CurrentMembership() actor: Membership,
    @Body() dto: ChangeMemberRoleDto,
  ) {
    return this.businesses.changeMemberRole(businessId, actor, user.id, userId, dto);
  }

  @Put(":businessId/members/:userId/permissions")
  @RequirePermission("members:manage")
  setPermissions(
    @Param("businessId", ParseUUIDPipe) businessId: string,
    @Param("userId", ParseUUIDPipe) userId: string,
    @CurrentUser() user: AuthUser,
    @CurrentMembership() actor: Membership,
    @Body() dto: SetPermissionOverridesDto,
  ) {
    return this.businesses.setPermissionOverrides(
      businessId,
      actor,
      user.id,
      userId,
      dto.overrides,
    );
  }

  @Put(":businessId/members/:userId/status")
  @RequirePermission("members:manage")
  setStatus(
    @Param("businessId", ParseUUIDPipe) businessId: string,
    @Param("userId", ParseUUIDPipe) userId: string,
    @CurrentUser() user: AuthUser,
    @CurrentMembership() actor: Membership,
    @Body() dto: ChangeMemberStatusDto,
  ) {
    return this.businesses.setMemberStatus(businessId, actor, user.id, userId, dto.status);
  }

  @Delete(":businessId/members/:userId")
  @RequirePermission("members:manage")
  @HttpCode(204)
  async remove(
    @Param("businessId", ParseUUIDPipe) businessId: string,
    @Param("userId", ParseUUIDPipe) userId: string,
    @CurrentUser() user: AuthUser,
    @CurrentMembership() actor: Membership,
  ) {
    await this.businesses.removeMember(businessId, actor, user.id, userId);
  }

  // ─── Invitations (côté entreprise) ───

  @Get(":businessId/invitations")
  @RequirePermission("members:manage")
  invitations(@Param("businessId", ParseUUIDPipe) businessId: string) {
    return this.businesses.listInvitations(businessId);
  }

  @Post(":businessId/invitations")
  @RequirePermission("members:manage")
  @RequireVerifiedPhone()
  @RateLimit({ name: "invite", limit: 30, windowSec: 3600, by: "user", failClosed: true })
  @HttpCode(201)
  invite(
    @Param("businessId", ParseUUIDPipe) businessId: string,
    @CurrentUser() user: AuthUser,
    @CurrentMembership() actor: Membership,
    @Body() dto: InviteMemberDto,
  ) {
    return this.businesses.invite(businessId, actor, user.id, dto);
  }

  @Delete(":businessId/invitations/:invitationId")
  @RequirePermission("members:manage")
  @HttpCode(204)
  async revoke(
    @Param("businessId", ParseUUIDPipe) businessId: string,
    @Param("invitationId", ParseUUIDPipe) invitationId: string,
    @CurrentUser() user: AuthUser,
  ) {
    await this.businesses.revokeInvitation(businessId, user.id, invitationId);
  }
}

/** Invitations reçues par l'utilisateur connecté (identifié par son numéro vérifié). */
@ApiTags("invitations")
@ApiBearerAuth()
@Controller("me/invitations")
export class MyInvitationsController {
  constructor(private readonly businesses: BusinessesService) {}

  @Get()
  @Authenticated()
  @RequireVerifiedPhone()
  list(@CurrentUser() user: AuthUser) {
    return this.businesses.myInvitations(user.id);
  }

  @Post(":invitationId/accept")
  @Authenticated()
  @RequireVerifiedPhone()
  @HttpCode(200)
  accept(
    @CurrentUser() user: AuthUser,
    @Param("invitationId", ParseUUIDPipe) invitationId: string,
  ) {
    return this.businesses.acceptInvitation(user.id, invitationId);
  }

  @Post(":invitationId/decline")
  @Authenticated()
  @RequireVerifiedPhone()
  @HttpCode(204)
  async decline(
    @CurrentUser() user: AuthUser,
    @Param("invitationId", ParseUUIDPipe) invitationId: string,
  ) {
    await this.businesses.declineInvitation(user.id, invitationId);
  }
}
