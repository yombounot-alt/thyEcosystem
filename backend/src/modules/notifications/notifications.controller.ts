import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
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
} from "@nestjs/common";
import { AllowRestricted, Authenticated } from "../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../kernel/auth/auth-types.js";
import { CurrentUser } from "../../kernel/auth/current-user.js";
import { PageQuery } from "../../kernel/dto.js";
import { RegisterDeviceDto, SetPreferencesDto, UnregisterDeviceDto } from "./dto.js";
import { NotificationsService } from "./notifications.service.js";

/** Boîte de réception, préférences et appareils de l'utilisateur connecté (sans notion d'entreprise). */
@ApiTags("notifications")
@ApiBearerAuth()
@Controller("me")
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get("notifications")
  @Authenticated()
  list(@CurrentUser() user: AuthUser, @Query() q: PageQuery) {
    return this.notifications.list(user.id, q.limit, q.cursor);
  }

  @Get("notifications/unread-count")
  @Authenticated()
  unread(@CurrentUser() user: AuthUser) {
    return this.notifications.unreadCount(user.id);
  }

  // Lire sa boîte n'est pas une action « métier » : permis même à un compte en lecture seule.
  @Post("notifications/read-all")
  @Authenticated()
  @AllowRestricted()
  @HttpCode(200)
  readAll(@CurrentUser() user: AuthUser) {
    return this.notifications.markAllRead(user.id);
  }

  @Post("notifications/:id/read")
  @Authenticated()
  @AllowRestricted()
  @HttpCode(200)
  read(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string) {
    return this.notifications.markRead(user.id, id);
  }

  @Get("notification-preferences")
  @Authenticated()
  preferences(@CurrentUser() user: AuthUser) {
    return this.notifications.preferences(user.id);
  }

  @Put("notification-preferences")
  @Authenticated()
  setPreferences(@CurrentUser() user: AuthUser, @Body() dto: SetPreferencesDto) {
    return this.notifications.setPreferences(user.id, dto.push);
  }

  @Post("devices")
  @Authenticated()
  @AllowRestricted()
  @HttpCode(204)
  async register(@CurrentUser() user: AuthUser, @Body() dto: RegisterDeviceDto) {
    await this.notifications.registerDevice(user.id, dto.token, dto.platform);
  }

  @Delete("devices")
  @Authenticated()
  @AllowRestricted()
  @HttpCode(204)
  async unregister(@CurrentUser() user: AuthUser, @Body() dto: UnregisterDeviceDto) {
    await this.notifications.unregisterDevice(user.id, dto.token);
  }
}
