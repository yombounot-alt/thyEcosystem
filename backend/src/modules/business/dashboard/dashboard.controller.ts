import { Controller, Get, Query } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import {
  CurrentBusiness,
  CurrentPermissions,
  CurrentUser,
} from "../../../kernel/auth/current-user.js";
import { DashboardService } from "./dashboard.service.js";
import { DashboardPeriodQuery } from "./dto/dashboard-period.query.js";
import { SalesChartQuery } from "./dto/sales-chart.query.js";
import { TopProductsQuery } from "./dto/top-products.query.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";

@ApiBearerAuth()
@ApiTags("dashboard")
@RequirePermission("reports:view")
@Controller("dashboard")
export class DashboardController {
  constructor(private readonly dashboard: DashboardService) {}

  @Get("summary")
  getSummary(
    @CurrentBusiness() businessId: string,
    @CurrentPermissions() permissions: string[],
    @Query() query: DashboardPeriodQuery,
  ) {
    return this.dashboard.getSummary(
      businessId,
      query,
      permissions.includes("finance:view_profit"),
    );
  }

  @Get("sales-chart")
  getSalesChart(@CurrentBusiness() businessId: string, @Query() query: SalesChartQuery) {
    return this.dashboard.getSalesChart(businessId, query);
  }

  @Get("top-products")
  getTopProducts(@CurrentBusiness() businessId: string, @Query() query: TopProductsQuery) {
    return this.dashboard.getTopProducts(businessId, query);
  }
}
