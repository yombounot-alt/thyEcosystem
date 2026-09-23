import { ApiPropertyOptional, OmitType, PartialType } from "@nestjs/swagger";
import { IsBoolean, IsOptional } from "class-validator";
import { CreateProductDto } from "./create-product.dto.js";

/** Stock is never edited through this DTO — it only moves via inventory movements. */
export class UpdateProductDto extends PartialType(
  OmitType(CreateProductDto, ["initialStock"] as const),
) {
  @ApiPropertyOptional({ description: "false = désactivé (masqué de la caisse), true = réactivé." })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
