import { IsIn, IsObject, IsOptional, IsString, Length, Matches, MaxLength } from "class-validator";
import { PHONE_E164 } from "../auth/dto.js";

/** Rôles assignables via l'API. OWNER en est exclu : le transfert de propriété est un flux dédié
 * (hors périmètre Phase 0), pas un simple changement de rôle — docs/blueprint/04-identity-access.md §4.2. */
export const ASSIGNABLE_ROLES = [
  "ADMIN",
  "MANAGER",
  "CASHIER",
  "STOCK_KEEPER",
  "ACCOUNTANT",
  "VIEWER",
] as const;

export class CreateBusinessDto {
  @IsString()
  @Length(1, 120)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  businessType?: string;

  @IsOptional()
  @Matches(/^[A-Z]{2}$/, { message: "country doit être un code ISO 3166-1 alpha-2 (ex. GN)" })
  country?: string;

  @IsOptional()
  @Matches(/^[A-Z]{3}$/, { message: "currency doit être un code ISO 4217 (ex. GNF)" })
  currency?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  timezone?: string;

  @IsOptional()
  @Matches(PHONE_E164)
  phone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  address?: string;
}

/**
 * Fiche modifiable de l'entreprise. Devise et pays sont figés après création : ils déterminent le
 * sens de tous les montants déjà enregistrés.
 */
export class UpdateBusinessDto {
  @IsOptional()
  @IsString()
  @Length(1, 120)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  businessType?: string;

  @IsOptional()
  @Matches(PHONE_E164)
  phone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  address?: string;
}

export class InviteMemberDto {
  @Matches(PHONE_E164, {
    message: "phone doit être au format international E.164 (ex. +224600000000)",
  })
  phone!: string;

  @IsIn(ASSIGNABLE_ROLES)
  roleCode!: (typeof ASSIGNABLE_ROLES)[number];
}

export class ChangeMemberRoleDto {
  @IsIn(ASSIGNABLE_ROLES)
  roleCode!: (typeof ASSIGNABLE_ROLES)[number];
}

export class ChangeMemberStatusDto {
  @IsIn(["ACTIVE", "SUSPENDED"])
  status!: "ACTIVE" | "SUSPENDED";
}

/**
 * Écarts individuels par rapport aux permissions du rôle : `{ "sales:refund": true, "credits:manage": false }`.
 * Objet vide = retour aux permissions par défaut du rôle. Les clés sont validées côté service
 * contre le catalogue (`core.permissions`).
 */
export class SetPermissionOverridesDto {
  @IsObject()
  overrides!: Record<string, boolean>;
}
