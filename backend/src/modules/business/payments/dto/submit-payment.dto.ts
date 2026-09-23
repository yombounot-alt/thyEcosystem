import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsDateString, IsNumber, IsOptional, IsString, MaxLength } from "class-validator";

/** What the payer says they did. It is a claim to check, never proof. */
export class SubmitPaymentDto {
  @ApiProperty({ example: "622 12 34 56", description: "Numéro utilisé pour envoyer l’argent." })
  @IsString()
  @MaxLength(30)
  payerPhone!: string;

  @ApiProperty({
    example: "MP240921.1234.A56789",
    description: "Référence / ID de la transaction (message de confirmation).",
  })
  @IsString()
  @MaxLength(80)
  transactionReference!: string;

  @ApiProperty({
    example: 250000,
    description: "Montant envoyé : doit être exactement le montant à payer.",
  })
  @IsNumber()
  amountSent!: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  payerName?: string;

  @ApiPropertyOptional({
    example: "2026-09-21T10:30:00.000Z",
    description: "Date et heure du paiement (par défaut : maintenant).",
  })
  @IsOptional()
  @IsDateString()
  paidAt?: string;
}
