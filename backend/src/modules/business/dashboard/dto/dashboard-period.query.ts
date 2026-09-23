import { ApiPropertyOptional } from "@nestjs/swagger";
import { Type } from "class-transformer";
import { IsDate, IsIn, IsOptional } from "class-validator";
import { PERIODS, type Period } from "../dashboard-period.js";

export class DashboardPeriodQuery {
  @ApiPropertyOptional({ enum: PERIODS, default: "today" })
  @IsOptional()
  @IsIn(PERIODS)
  period?: Period;

  @ApiPropertyOptional({ description: "Requis si period=custom." })
  @IsOptional()
  @Type(() => Date)
  @IsDate()
  from?: Date;

  @ApiPropertyOptional({ description: "Requis si period=custom." })
  @IsOptional()
  @Type(() => Date)
  @IsDate()
  to?: Date;
}
