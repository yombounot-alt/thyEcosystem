import { Body, Controller, Get, Patch } from "@nestjs/common";
import { Authenticated } from "../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../kernel/auth/auth-types.js";
import { CurrentUser } from "../../kernel/auth/current-user.js";
import { UpdateMeDto } from "./dto.js";
import { UsersService } from "./users.service.js";

@Controller("me")
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get()
  @Authenticated()
  me(@CurrentUser() user: AuthUser) {
    return this.users.me(user.id);
  }

  @Patch()
  @Authenticated()
  update(@CurrentUser() user: AuthUser, @Body() dto: UpdateMeDto) {
    return this.users.update(user.id, dto);
  }

  @Get("businesses")
  @Authenticated()
  businesses(@CurrentUser() user: AuthUser) {
    return this.users.myBusinesses(user.id);
  }
}
