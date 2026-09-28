import { IsIn, IsObject, IsString, Length } from "class-validator";

export class RegisterDeviceDto {
  @IsString()
  @Length(20, 4096)
  token!: string;

  @IsIn(["android", "ios", "web"])
  platform!: "android" | "ios" | "web";
}

export class UnregisterDeviceDto {
  @IsString()
  @Length(20, 4096)
  token!: string;
}

/** `{ "BUSINESS_WELCOME": false }` — push uniquement ; les types obligatoires sont refusés. */
export class SetPreferencesDto {
  @IsObject()
  push!: Record<string, boolean>;
}
