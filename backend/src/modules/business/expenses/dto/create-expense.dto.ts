import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsDateString, IsIn, IsNumber, IsOptional, IsPositive, IsString } from "class-validator";

export const EXPENSE_CATEGORIES = [
  "transport",
  "loyer",
  "salaire",
  "electricite",
  "internet",
  "achat",
  "maintenance",
  "autre",
] as const;

export class CreateExpenseDto {
  @ApiProperty({ enum: EXPENSE_CATEGORIES })
  @IsIn(EXPENSE_CATEGORIES)
  category!: (typeof EXPENSE_CATEGORIES)[number];

  @ApiProperty({ example: 50000 })
  @IsNumber()
  @IsPositive()
  amount!: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional({ example: "2026-09-16", description: "Défaut : aujourd'hui." })
  @IsOptional()
  @IsDateString()
  expenseDate?: string;
}
