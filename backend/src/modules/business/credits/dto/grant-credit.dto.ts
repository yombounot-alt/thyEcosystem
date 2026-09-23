import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsDateString, IsNumber, IsOptional, IsPositive, IsString } from "class-validator";

export class GrantCreditDto {
  @ApiProperty({ example: 350000 })
  @IsNumber()
  @IsPositive()
  amount!: number;

  @ApiPropertyOptional({ example: "2026-09-20" })
  @IsOptional()
  @IsDateString()
  dueDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  note?: string;
}
