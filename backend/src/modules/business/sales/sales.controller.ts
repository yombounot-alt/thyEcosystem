import { Body, Controller, Get, Param, Post, Query } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentBusiness, CurrentUser } from "../../../kernel/auth/current-user.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../../kernel/auth/auth-types.js";
import { CreateSaleDto } from "./dto/create-sale.dto.js";
import { ListSalesQuery } from "./dto/list-sales.query.js";
import { SalesService } from "./sales.service.js";

@ApiBearerAuth()
@ApiTags("sales")
@RequirePermission("sales:view")
@Controller("sales")
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Post()
  @RequirePermission("sales:create")
  checkout(
    @CurrentBusiness() businessId: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: CreateSaleDto,
  ) {
    return this.sales.checkout(businessId, dto, user.id);
  }

  @Get()
  findAll(@CurrentBusiness() businessId: string, @Query() query: ListSalesQuery) {
    return this.sales.findAll(businessId, query);
  }

  @Get(":id")
  findOne(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.sales.findOne(businessId, id);
  }

  @Post(":id/void")
  @RequirePermission("sales:refund")
  voidSale(
    @CurrentBusiness() businessId: string,
    @CurrentUser() user: AuthUser,
    @Param("id") id: string,
  ) {
    return this.sales.void(businessId, id, user.id);
  }
}
