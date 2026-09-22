import { Body, Controller, HttpCode, Post } from "@nestjs/common";
import { AllowRestricted, Authenticated, Public, RateLimit } from "../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../kernel/auth/auth-types.js";
import { CurrentUser, Meta, type ClientMeta } from "../../kernel/auth/current-user.js";
import { AuthService } from "./auth.service.js";
import { OtpRequestDto, OtpVerifyDto, RefreshDto } from "./dto.js";

@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post("otp/request")
  @Public()
  @HttpCode(204)
  @RateLimit({ name: "otp-request", limit: 3, windowSec: 600, by: "ip+phone", failClosed: true })
  async otpRequest(@Body() dto: OtpRequestDto) {
    await this.auth.otpRequest(dto.phone);
  }

  @Post("otp/verify")
  @Public()
  @HttpCode(200)
  @RateLimit({ name: "otp-verify", limit: 10, windowSec: 600, by: "ip+phone", failClosed: true })
  otpVerify(@Body() dto: OtpVerifyDto, @Meta() meta: ClientMeta) {
    return this.auth.otpVerify(dto.phone, dto.code, meta);
  }

  @Post("refresh")
  @Public()
  @HttpCode(200)
  @RateLimit({ name: "refresh", limit: 30, windowSec: 60, by: "ip" })
  refresh(@Body() dto: RefreshDto, @Meta() meta: ClientMeta) {
    return this.auth.refresh(dto.refreshToken, meta);
  }

  @Post("logout")
  @Authenticated()
  @AllowRestricted()
  @HttpCode(204)
  async logout(@Body() dto: RefreshDto, @CurrentUser() user: AuthUser) {
    await this.auth.logout(dto.refreshToken, user.id);
  }
}
