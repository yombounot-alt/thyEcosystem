import { ApiProperty, ApiPropertyOptional, PartialType } from "@nestjs/swagger";
import { IsBoolean, IsIn, IsOptional, IsString, MaxLength } from "class-validator";
import { PAYMENT_PROVIDERS, type PaymentProvider } from "../payment-rules.js";

export class CreatePaymentMethodDto {
  @ApiProperty({ enum: PAYMENT_PROVIDERS })
  @IsIn(PAYMENT_PROVIDERS)
  provider!: PaymentProvider;

  @ApiPropertyOptional({
    example: "Orange Money",
    description: "Nom montré au client (par défaut : celui du type).",
  })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  displayName?: string;

  @ApiPropertyOptional({ description: "Titulaire du compte, montré au client." })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  accountName?: string;

  @ApiPropertyOptional({
    example: "622 12 34 56",
    description: "Numéro Orange Money / Mobile Money du propriétaire.",
  })
  @IsOptional()
  @IsString()
  @MaxLength(30)
  phoneNumber?: string;

  @ApiPropertyOptional({ description: "Code marchand du propriétaire." })
  @IsOptional()
  @IsString()
  @MaxLength(40)
  merchantCode?: string;

  @ApiPropertyOptional({
    description: "Étapes montrées au client, une par ligne (vide = étapes par défaut).",
  })
  @IsOptional()
  @IsString()
  @MaxLength(1200)
  instructions?: string;

  @ApiPropertyOptional({
    example: "*144*1*{numero}*{montant}#",
    description:
      "Code composé par « Payer maintenant ». Il dépend de l’opérateur et du pays : à définir par le propriétaire. Accepte {numero}, {montant} et {code}.",
  })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  ussdCode?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdatePaymentMethodDto extends PartialType(CreatePaymentMethodDto) {}
