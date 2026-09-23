import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsOptional, IsString, MinLength } from "class-validator";

export class CreateCustomerDto {
  @ApiProperty({ example: "Mamadou Diallo" })
  @IsString()
  @MinLength(2)
  fullName!: string;

  @ApiPropertyOptional({ example: "+224655555555" })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}
