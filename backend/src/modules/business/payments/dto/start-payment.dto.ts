import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { Type } from "class-transformer";
import {
  ArrayMinSize,
  IsArray,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from "class-validator";
import { SaleItemInputDto } from "../../sales/dto/create-sale.dto.js";

/**
 * The basket the customer is about to pay for. There is deliberately no amount: it is computed by
 * the server from the catalogue, and the whole total is paid.
 */
export class StartPaymentDto {
  @ApiProperty({ type: [SaleItemInputDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SaleItemInputDto)
  items!: SaleItemInputDto[];

  @ApiPropertyOptional({ example: 5000, description: "Réduction globale sur le sous-total." })
  @IsOptional()
  @IsNumber()
  @Min(0)
  discountTotal?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiProperty({ description: "Le moyen de paiement (actif) choisi par le client." })
  @IsUUID()
  paymentMethodId!: string;

  @ApiProperty({
    description:
      "Clé d'idempotence (une par panier) : la redemander renvoie le même paiement. C'est aussi la clé de la vente créée une fois le paiement validé.",
  })
  @IsString()
  @MinLength(8)
  @MaxLength(64)
  clientRequestId!: string;
}
