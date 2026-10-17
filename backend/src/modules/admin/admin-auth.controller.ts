import { Body, Controller, Get, HttpCode, Inject, Post, Req, Res, UseGuards } from "@nestjs/common";
import { ApiExcludeController } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { Public, RateLimit } from "../../kernel/auth/auth-types.js";
import { CONFIG, type AppConfig } from "../../kernel/config/config.js";
import { CryptoService } from "../../kernel/security/crypto.service.js";
import { StaffLoginDto, TotpCodeDto } from "./dto.js";
import { StaffAuthService, type StaffPrincipal } from "./staff-auth.service.js";
import { AllowMfaPending, CurrentStaff, STAFF_SESSION_COOKIE, StaffGuard } from "./staff.guard.js";

/**
 * Connexion du staff. `@Public()` : ces routes échappent aux gardes de l'app (JWT client) ; elles
 * ont leur propre garde (StaffGuard). Absentes du contrat OpenAPI public (ApiExcludeController).
 */
@ApiExcludeController()
@Public()
@Controller("admin/v1/auth")
export class AdminAuthController {
  constructor(
    private readonly auth: StaffAuthService,
    private readonly crypto: CryptoService,
    @Inject(CONFIG) private readonly cfg: AppConfig,
  ) {}

  private setSessionCookie(res: Response, token: string) {
    res.cookie(STAFF_SESSION_COOKIE, token, {
      httpOnly: true,
      secure: this.cfg.admin.cookieSecure,
      sameSite: "strict",
      path: "/admin/v1",
      maxAge: this.cfg.admin.sessionMaxHours * 3600 * 1000,
    });
  }

  @Post("login")
  @HttpCode(200)
  @RateLimit({ name: "admin-login", limit: 10, windowSec: 600, by: "ip", failClosed: true })
  async login(
    @Body() dto: StaffLoginDto,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const session = await this.auth.login(dto.email, dto.password, {
      ...(req.ip ? { ip: req.ip } : {}),
      userAgent: (req.headers["user-agent"] ?? "").slice(0, 200),
    });
    this.setSessionCookie(res, session.sessionToken);
    return { csrfToken: session.csrfToken, next: session.next };
  }

  /** Qui est connecté, où en est la double authentification, et un jeton anti-CSRF neuf. */
  @Get("session")
  @UseGuards(StaffGuard)
  @AllowMfaPending()
  async session(@CurrentStaff() staff: StaffPrincipal) {
    return {
      staff: {
        id: staff.staffId,
        email: staff.email,
        fullName: staff.fullName,
        roles: staff.roles,
        permissions: [...staff.permissions].sort(),
      },
      mfaVerified: staff.mfaVerified,
      mfaEnrollmentRequired: staff.mfaEnrollmentRequired,
      csrfToken: await this.auth.rotateCsrf(staff),
    };
  }

  @Post("totp/setup")
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @AllowMfaPending()
  setupTotp(@CurrentStaff() staff: StaffPrincipal) {
    return this.auth.setupTotp(staff);
  }

  @Post("totp/confirm")
  @HttpCode(204)
  @UseGuards(StaffGuard)
  @AllowMfaPending()
  @RateLimit({ name: "admin-totp", limit: 10, windowSec: 600, by: "ip", failClosed: true })
  async confirmTotp(
    @CurrentStaff() staff: StaffPrincipal,
    @Body() dto: TotpCodeDto,
    @Req() req: Request,
  ) {
    await this.auth.confirmTotp(staff, dto.code, this.crypto.ipHash(req.ip));
  }

  @Post("logout")
  @HttpCode(204)
  @UseGuards(StaffGuard)
  @AllowMfaPending()
  async logout(@CurrentStaff() staff: StaffPrincipal, @Res({ passthrough: true }) res: Response) {
    await this.auth.logout(staff);
    res.clearCookie(STAFF_SESSION_COOKIE, { path: "/admin/v1" });
  }
}
