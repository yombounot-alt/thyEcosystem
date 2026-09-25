import { Controller, Get, Query } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentBusiness } from "../../../kernel/auth/current-user.js";
import { CreditsService } from "./credits.service.js";
import { ListCreditsQuery } from "./dto/list-credits.query.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";

@ApiBearerAuth()
@ApiTags("credits")
@RequirePermission("customers:view")
@Controller("credits")
export class CreditsController {
  constructor(private readonly credits: CreditsService) {}

  @Get()
  findAll(@CurrentBusiness() businessId: string, @Query() query: ListCreditsQuery) {
    return this.credits.listBusinessWide(businessId, query);
  }
}
