import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import {
  CurrentBusiness,
  CurrentPermissions,
  CurrentUser,
} from "../../../kernel/auth/current-user.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../../kernel/auth/auth-types.js";
import { CreateExpenseDto } from "./dto/create-expense.dto.js";
import { ListExpensesQuery } from "./dto/list-expenses.query.js";
import { UpdateExpenseDto } from "./dto/update-expense.dto.js";
import { ExpensesService } from "./expenses.service.js";

@ApiBearerAuth()
@ApiTags("expenses")
@RequirePermission("expenses:view")
@Controller("expenses")
export class ExpensesController {
  constructor(private readonly expenses: ExpensesService) {}

  @Post()
  @RequirePermission("expenses:manage")
  create(
    @CurrentBusiness() businessId: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: CreateExpenseDto,
  ) {
    return this.expenses.create(businessId, dto, user.id);
  }

  @Get()
  findAll(@CurrentBusiness() businessId: string, @Query() query: ListExpensesQuery) {
    return this.expenses.findAll(businessId, query);
  }

  @Get(":id")
  findOne(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.expenses.findOne(businessId, id);
  }

  @Patch(":id")
  @RequirePermission("expenses:manage")
  update(
    @CurrentBusiness() businessId: string,
    @Param("id") id: string,
    @Body() dto: UpdateExpenseDto,
  ) {
    return this.expenses.update(businessId, id, dto);
  }

  @Delete(":id")
  @RequirePermission("expenses:manage")
  remove(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.expenses.remove(businessId, id);
  }
}
