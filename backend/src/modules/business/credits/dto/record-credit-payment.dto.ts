import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsIn, IsNumber, IsOptional, IsPositive, IsString } from "class-validator";

export const CREDIT_PAYMENT_METHODS = ["cash", "mobile_money", "card", "other"] as const;

export class RecordCreditPaymentDto {
  @ApiProperty({ example: 100000 })
  @IsNumber()
  @IsPositive()
  amount!: number;

  @ApiProperty({ enum: CREDIT_PAYMENT_METHODS, default: "cash" })
  @IsIn(CREDIT_PAYMENT_METHODS)
  method!: (typeof CREDIT_PAYMENT_METHODS)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  note?: string;
}
