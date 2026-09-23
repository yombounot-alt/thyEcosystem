import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import {
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  Min,
  MinLength,
} from "class-validator";

export class CreateProductDto {
  @ApiProperty({ example: "Riz local 25kg" })
  @IsString()
  @MinLength(1)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  categoryId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  sku?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  barcode?: string;

  @ApiPropertyOptional({ default: "unite" })
  @IsOptional()
  @IsString()
  unit?: string;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  purchasePrice?: number;

  @ApiProperty({ example: 150000 })
  @IsNumber()
  @Min(0)
  salePrice!: number;

  @ApiPropertyOptional({ description: 'Stock initial à créditer via un mouvement "initial".' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  initialStock?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @IsPositive()
  lowStockThreshold?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;
}
