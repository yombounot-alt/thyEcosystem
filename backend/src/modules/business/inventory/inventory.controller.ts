import { Body, Controller, Get, Post, Query } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import {
  CurrentBusiness,
  CurrentPermissions,
  CurrentUser,
} from "../../../kernel/auth/current-user.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../../kernel/auth/auth-types.js";
import { CreateMovementDto } from "./dto/create-movement.dto.js";
import { ListMovementsQuery } from "./dto/list-movements.query.js";
import { InventoryService } from "./inventory.service.js";

@ApiBearerAuth()
@ApiTags("inventory")
@RequirePermission("inventory:view")
@Controller("inventory")
export class InventoryController {
  constructor(private readonly inventory: InventoryService) {}

  @Post("movements")
  @RequirePermission("inventory:adjust")
  recordMovement(
    @CurrentBusiness() businessId: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: CreateMovementDto,
  ) {
    return this.inventory.recordManualMovement(businessId, dto, user.id);
  }

  @Get("movements")
  findAll(@CurrentBusiness() businessId: string, @Query() query: ListMovementsQuery) {
    return this.inventory.findAll(businessId, query);
  }
}
