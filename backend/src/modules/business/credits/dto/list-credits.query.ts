import { ApiPropertyOptional } from "@nestjs/swagger";
import { Type } from "class-transformer";
import { IsIn, IsInt, IsOptional, Min } from "class-validator";

/** 'outstanding' is a shortcut for "still owed": open + partially_paid. */
export const CREDIT_STATUSES = ["open", "partially_paid", "paid", "void", "outstanding"] as const;

export class ListCreditsQuery {
  @ApiPropertyOptional({ enum: CREDIT_STATUSES })
  @IsOptional()
  @IsIn(CREDIT_STATUSES)
  status?: (typeof CREDIT_STATUSES)[number];

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  pageSize?: number;
}
