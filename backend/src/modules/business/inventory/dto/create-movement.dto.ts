import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsIn, IsNumber, IsOptional, IsPositive, IsString, IsUUID } from "class-validator";
import { MANUAL_MOVEMENT_TYPES } from "../inventory-movement.types.js";

export class CreateMovementDto {
  @ApiProperty()
  @IsUUID()
  productId!: string;

  @ApiProperty({ enum: MANUAL_MOVEMENT_TYPES })
  @IsIn(MANUAL_MOVEMENT_TYPES)
  type!: (typeof MANUAL_MOVEMENT_TYPES)[number];

  @ApiProperty({ example: 10 })
  @IsNumber()
  @IsPositive()
  quantity!: number;

  @ApiPropertyOptional({ example: 5000 })
  @IsOptional()
  @IsNumber()
  unitCost?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  note?: string;
}
