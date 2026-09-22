import { IsString, Length, Matches } from "class-validator";

export const PHONE_E164 = /^\+[1-9][0-9]{6,14}$/;

export class OtpRequestDto {
  @Matches(PHONE_E164, {
    message: "phone doit être au format international E.164 (ex. +224600000000)",
  })
  phone!: string;
}

export class OtpVerifyDto {
  @Matches(PHONE_E164)
  phone!: string;

  @Matches(/^\d{6}$/)
  code!: string;
}

export class RefreshDto {
  @IsString()
  @Length(20, 200)
  refreshToken!: string;
}
