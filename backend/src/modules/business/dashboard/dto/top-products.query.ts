import { ApiPropertyOptional } from "@nestjs/swagger";
import { Type } from "class-transformer";
import { IsInt, IsOptional, Min } from "class-validator";
import { DashboardPeriodQuery } from "./dashboard-period.query.js";

export class TopProductsQuery extends DashboardPeriodQuery {
  @ApiPropertyOptional({ default: 5 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  limit?: number;
}
