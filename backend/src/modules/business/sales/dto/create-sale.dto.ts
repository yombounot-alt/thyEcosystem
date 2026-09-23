import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { Type } from "class-transformer";
import {
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from "class-validator";

export const PAYMENT_METHODS = ["cash", "mobile_money", "card", "other"] as const;

export class SaleItemInputDto {
  @ApiProperty()
  @IsUUID()
  productId!: string;

  @ApiProperty({ example: 2 })
  @IsNumber()
  @IsPositive()
  quantity!: number;
}

export class SalePaymentInputDto {
  @ApiProperty({ enum: PAYMENT_METHODS })
  @IsIn(PAYMENT_METHODS)
  method!: (typeof PAYMENT_METHODS)[number];

  @ApiProperty({ example: 45000 })
  @IsNumber()
  @IsPositive()
  amount!: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  providerReference?: string;
}

export class CreateSaleDto {
  @ApiProperty({ type: [SaleItemInputDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SaleItemInputDto)
  items!: SaleItemInputDto[];

  @ApiPropertyOptional({
    type: [SalePaymentInputDto],
    description: "Peut être vide pour une vente entièrement à crédit (customerId requis).",
  })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SalePaymentInputDto)
  payments?: SalePaymentInputDto[];

  @ApiPropertyOptional({ example: 5000, description: "Réduction globale sur le sous-total." })
  @IsOptional()
  @IsNumber()
  @Min(0)
  discountTotal?: number;

  @ApiPropertyOptional({
    description: "Requis si le paiement ne couvre pas le total (vente à crédit).",
  })
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({
    description:
      "Clé d'idempotence générée par le client : rejouer la même requête renvoie la vente d'origine au lieu d'en créer une seconde.",
  })
  @IsOptional()
  @IsString()
  @MinLength(8)
  @MaxLength(64)
  clientRequestId?: string;

  @ApiPropertyOptional({
    example: "2026-09-19T10:30:00.000Z",
    description:
      "Date réelle de la vente quand elle a été saisie hors ligne puis envoyée plus tard (ISO 8601). Une date future est ramenée à maintenant ; au-delà de 60 jours dans le passé, la vente est refusée.",
  })
  @IsOptional()
  @IsDateString()
  soldAt?: string;

  @ApiPropertyOptional({
    description:
      "Vente encaissée hors ligne : les marchandises sont déjà parties, donc la vente est enregistrée même si le stock du serveur est devenu insuffisant (le stock peut alors passer sous zéro, à régulariser par un inventaire) ou si le produit a été désactivé entre-temps.",
  })
  @IsOptional()
  @IsBoolean()
  offline?: boolean;
}
