import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Body, Controller, HttpCode, Post } from "@nestjs/common";
import { AllowRestricted, Authenticated, Public, RateLimit } from "../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../kernel/auth/auth-types.js";
import { CurrentUser, Meta, type ClientMeta } from "../../kernel/auth/current-user.js";
import { AuthService } from "./auth.service.js";
import { OtpRequestDto, OtpVerifyDto, RefreshDto } from "./dto.js";

@ApiTags("auth")
@ApiBearerAuth()
@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post("otp/request")
  @Public()
  @HttpCode(204)
  // Par numéro (ip+phone, plus les quotas d'OtpService) ET par IP seule, contre la fraude au SMS :
  // une IP ne peut pas viser des milliers de numéros. Large par IP car les opérateurs mobiles
  // partagent une IP publique entre beaucoup d'abonnés (CGNAT) ; à réviser avec le trafic réel.
  @RateLimit(
    { name: "otp-request", limit: 3, windowSec: 600, by: "ip+phone", failClosed: true },
    { name: "otp-request-ip", limit: 20, windowSec: 600, by: "ip", failClosed: true },
    { name: "otp-request-ip-day", limit: 100, windowSec: 86_400, by: "ip", failClosed: true },
  )
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
    return this.auth.refresh(dto.refreshToken, meta, dto.businessId);
  }

  @Post("logout")
  @Authenticated()
  @AllowRestricted()
  @HttpCode(204)
  async logout(@Body() dto: RefreshDto, @CurrentUser() user: AuthUser) {
    await this.auth.logout(dto.refreshToken, user.id);
  }
}
