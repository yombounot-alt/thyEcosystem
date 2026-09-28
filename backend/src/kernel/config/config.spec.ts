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

describe("loadConfig — stockage (STORAGE_DRIVER)", () => {
  const S3 = {
    STORAGE_DRIVER: "s3",
    S3_ENDPOINT: "https://storage.googleapis.com",
    S3_BUCKET: "thy-staging-storage",
    S3_ACCESS_KEY_ID: "GOOG1EXAMPLE",
    S3_SECRET_ACCESS_KEY: "secret-example",
  };

  it("disque local par défaut", () => {
    const cfg = loadConfig({ NODE_ENV: "development" });
    expect(cfg.storage).toEqual({ driver: "local", localPath: "./uploads" });
  });

  it("s3 : lit toute la configuration, avec des défauts pour la région et l'adressage", () => {
    const cfg = loadConfig({ NODE_ENV: "development", ...S3 });
    expect(cfg.storage.driver).toBe("s3");
    expect(cfg.storage.s3).toEqual({
      endpoint: "https://storage.googleapis.com",
      bucket: "thy-staging-storage",
      accessKeyId: "GOOG1EXAMPLE",
      secretAccessKey: "secret-example",
      region: "auto",
      forcePathStyle: true,
    });
  });

  it("s3 : refuse une configuration incomplète en nommant ce qui manque", () => {
    expect(() =>
      loadConfig({ NODE_ENV: "development", STORAGE_DRIVER: "s3", S3_ENDPOINT: "http://x" }),
    ).toThrow(/bucket, accessKeyId, secretAccessKey/);
  });

  it("refuse un pilote inconnu", () => {
    expect(() => loadConfig({ NODE_ENV: "development", STORAGE_DRIVER: "ftp" })).toThrow(
      /STORAGE_DRIVER invalide/,
    );
  });

  it("production : le disque local est refusé, s3 en http aussi", () => {
    expect(() => loadConfig({ ...PROD_BASE })).toThrow(/disque local est interdit/);
    expect(() => loadConfig({ ...PROD_BASE, ...S3, S3_ENDPOINT: "http://minio:9000" })).toThrow(
      /S3_ENDPOINT doit être en https/,
    );
  });

  it("production : s3 en https ne soulève plus d'erreur de stockage", () => {
    try {
      loadConfig({ ...PROD_BASE, ...S3 });
    } catch (e) {
      // D'autres adaptateurs manquent encore (SMS, push) : seul le stockage est vérifié ici.
      expect((e as Error).message).not.toMatch(/stockage|S3_ENDPOINT/);
    }
  });
});
