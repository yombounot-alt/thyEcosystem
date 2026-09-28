import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Controller, Get, Param, ParseUUIDPipe } from "@nestjs/common";
import { Authenticated, RequireMembership } from "../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../kernel/auth/auth-types.js";
import { CurrentUser } from "../../kernel/auth/current-user.js";
import { Db } from "../../kernel/db/db.service.js";
import { FeatureFlagsService } from "./feature-flags.service.js";
import { SubscriptionsService } from "./subscriptions.service.js";

@ApiTags("subscriptions")
@ApiBearerAuth()
@Controller()
export class SubscriptionsController {
  constructor(
    private readonly subscriptions: SubscriptionsService,
    private readonly flags: FeatureFlagsService,
    private readonly db: Db,
  ) {}

  /** Offre de l'entreprise, droits effectifs et occupation — tout membre peut la consulter. */
  @Get("businesses/:businessId/subscription")
  @RequireMembership()
  subscription(@Param("businessId", ParseUUIDPipe) businessId: string) {
    return this.subscriptions.summary(businessId);
  }

  @Get("me/feature-flags")
  @Authenticated()
  async featureFlags(@CurrentUser() user: AuthUser) {
    const country = user.activeBusinessId
      ? ((
          await this.db.withTenant({ userId: user.id }, (tx) =>
            this.db.one<{ country: string }>(
              "SELECT country FROM core.businesses WHERE id = $1",
              [user.activeBusinessId],
              tx,
            ),
          )
        )?.country ?? null)
      : null;
    return { flags: await this.flags.enabledFor(user.id, country) };
  }
}
