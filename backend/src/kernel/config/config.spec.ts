import { loadConfig } from "./config.js";

const PROD_BASE = {
  NODE_ENV: "production",
  JWT_SECRET: "x".repeat(48),
  HMAC_PEPPER: "y".repeat(48),
  DATABASE_URL: "postgres://thy_app:pw@db:5432/thy",
  MIGRATOR_DATABASE_URL: "postgres://thy_migrator:pw@db:5432/thy",
};

describe("loadConfig — code OTP fixe de développement (DEV_FIXED_OTP)", () => {
  it("est transmis à la configuration hors production", () => {
    const cfg = loadConfig({ NODE_ENV: "development", DEV_FIXED_OTP: "123456" });
    expect(cfg.sms.fixedOtp).toBe("123456");
  });

  it("n'existe pas par défaut", () => {
    expect(loadConfig({ NODE_ENV: "development" }).sms.fixedOtp).toBeUndefined();
    expect(loadConfig({ NODE_ENV: "development", DEV_FIXED_OTP: "" }).sms.fixedOtp).toBeUndefined();
  });

  it("doit contenir exactement 6 chiffres", () => {
    for (const bad of ["12345", "1234567", "abcdef", "12 456"]) {
      expect(() => loadConfig({ NODE_ENV: "development", DEV_FIXED_OTP: bad })).toThrow(
        /6 chiffres/,
      );
    }
  });

  it("est refusé en production (code OTP prévisible)", () => {
    expect(() => loadConfig({ ...PROD_BASE, DEV_FIXED_OTP: "123456" })).toThrow(
      /DEV_FIXED_OTP est interdit en production/,
    );
  });

  it("la production reste refusée avec l'adaptateur console, avec ou sans code fixe", () => {
    expect(() => loadConfig({ ...PROD_BASE })).toThrow(/SMS_DRIVER/);
  });
});
