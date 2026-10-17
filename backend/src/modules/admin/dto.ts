import { Type } from "class-transformer";
import {
  IsArray,
  IsBoolean,
  IsDateString,
  IsEmail,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
} from "class-validator";

export class StaffLoginDto {
  @IsEmail()
  @MaxLength(200)
  email!: string;

  @IsString()
  @Length(1, 200)
  password!: string;
}

export class TotpCodeDto {
  @Matches(/^\d{6}$/, { message: "code doit contenir 6 chiffres" })
  code!: string;
}

/** Toute action modifiante de l'admin exige un motif (docs/blueprint/09-admin.md §5). */
export class ReasonDto {
  @IsString()
  @Length(5, 500, { message: "motif requis (5 à 500 caractères)" })
  reason!: string;
}

export class UserSearchQuery {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  q?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  cursor?: string;
}

export class AuditQuery {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  action?: string;

  @IsOptional()
  @IsIn(["user", "staff", "system"])
  actorType?: "user" | "staff" | "system";

  @IsOptional()
  @IsString()
  @MaxLength(100)
  actorId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  targetId?: string;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  cursor?: string;
}

export class UpsertFlagDto extends ReasonDto {
  @IsString()
  @Length(1, 300)
  description!: string;

  @IsBoolean()
  enabled!: boolean;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(100)
  rolloutPercent!: number;

  /** Codes pays ISO (ex. ["GN"]) ; absent = tous les pays. */
  @IsOptional()
  @IsArray()
  @Matches(/^[A-Z]{2}$/, { each: true })
  countries?: string[];
}

/** Dérogation d'offre : `value` absent ou null = illimité. */
export class SetOverrideDto extends ReasonDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  value?: number | null;

  @IsOptional()
  @IsDateString()
  expiresAt?: string;
}
