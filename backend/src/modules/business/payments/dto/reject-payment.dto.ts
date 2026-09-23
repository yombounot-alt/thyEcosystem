import { ApiPropertyOptional } from "@nestjs/swagger";
import { IsOptional, IsString, MaxLength } from "class-validator";

export class RejectPaymentDto {
  @ApiPropertyOptional({
    example: "Transaction introuvable",
    description: "Motif montré au client.",
  })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  reason?: string;
}
