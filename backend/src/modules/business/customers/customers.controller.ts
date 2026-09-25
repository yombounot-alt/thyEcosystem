import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentBusiness, CurrentUser } from "../../../kernel/auth/current-user.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../../kernel/auth/auth-types.js";
import { CreditsService } from "../credits/credits.service.js";
import { GrantCreditDto } from "../credits/dto/grant-credit.dto.js";
import { RecordCreditPaymentDto } from "../credits/dto/record-credit-payment.dto.js";
import { CustomersService } from "./customers.service.js";
import { CreateCustomerDto } from "./dto/create-customer.dto.js";
import { ListCustomersQuery } from "./dto/list-customers.query.js";
import { UpdateCustomerDto } from "./dto/update-customer.dto.js";

@ApiBearerAuth()
@ApiTags("customers")
@RequirePermission("customers:view")
@Controller("customers")
export class CustomersController {
  constructor(
    private readonly customers: CustomersService,
    private readonly credits: CreditsService,
  ) {}

  @Post()
  @RequirePermission("customers:manage")
  create(@CurrentBusiness() businessId: string, @Body() dto: CreateCustomerDto) {
    return this.customers.create(businessId, dto);
  }

  @Get()
  findAll(@CurrentBusiness() businessId: string, @Query() query: ListCustomersQuery) {
    return this.customers.findAll(businessId, query);
  }

  @Get(":id")
  findOne(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.customers.findOne(businessId, id);
  }

  @Patch(":id")
  @RequirePermission("customers:manage")
  update(
    @CurrentBusiness() businessId: string,
    @Param("id") id: string,
    @Body() dto: UpdateCustomerDto,
  ) {
    return this.customers.update(businessId, id, dto);
  }

  @Delete(":id")
  @RequirePermission("customers:manage")
  remove(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.customers.remove(businessId, id);
  }

  @Get(":id/credits")
  listCredits(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.credits.listForCustomer(businessId, id);
  }

  @Get(":id/statement")
  statement(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.credits.getStatement(businessId, id);
  }

  @Post(":id/credits")
  @RequirePermission("credits:manage")
  grantCredit(
    @CurrentBusiness() businessId: string,
    @CurrentUser() user: AuthUser,
    @Param("id") id: string,
    @Body() dto: GrantCreditDto,
  ) {
    return this.credits.grantManual(businessId, id, dto, user.id);
  }

  @Post(":id/credit-payments")
  @RequirePermission("credits:manage")
  recordCreditPayment(
    @CurrentBusiness() businessId: string,
    @CurrentUser() user: AuthUser,
    @Param("id") id: string,
    @Body() dto: RecordCreditPaymentDto,
  ) {
    return this.credits.recordPayment(businessId, id, dto, user.id);
  }
}
