import { Inject, Injectable } from "@nestjs/common";
import { hash as argonHash, verify as argonVerify, type Algorithm } from "@node-rs/argon2";
import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { CONFIG, type AppConfig } from "../config/config.js";

// Paramètres argon2id : minimum recommandé OWASP (19 MiB, t=2, p=1).
const ARGON = {
  algorithm: 2 as Algorithm /* Argon2id */,
  memoryCost: 19456,
  timeCost: 2,
  parallelism: 1,
} as const;

export const sha256 = (input: string | Buffer): Buffer =>
  createHash("sha256").update(input).digest();

/** Comparaison à temps constant de deux buffers (longueurs différentes ⇒ faux, sans fuite). */
export function safeEqual(a: Buffer, b: Buffer): boolean {
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

@Injectable()
export class CryptoService {
  private dummyHash?: Promise<string>;

  constructor(@Inject(CONFIG) private readonly cfg: AppConfig) {}

  hashPassword(password: string): Promise<string> {
    return argonHash(password, ARGON);
  }

  async verifyPassword(hash: string, password: string): Promise<boolean> {
    try {
      return await argonVerify(hash, password);
    } catch {
      return false;
    }
  }

  /** Vérification factice : égalise le temps de réponse quand le compte n'existe pas (pas d'oracle de timing). */
  async verifyDummy(password: string): Promise<void> {
    this.dummyHash ??= this.hashPassword("dummy-password-for-timing-equalisation");
    await this.verifyPassword(await this.dummyHash, password);
  }

  /** Jeton opaque 256 bits (refresh token, jeton d'invitation…). */
  randomToken(bytes = 32): string {
    return randomBytes(bytes).toString("base64url");
  }

  /** Code OTP à 6 chiffres, tirage cryptographique. */
  randomOtp(): string {
    return String(randomInt(0, 1_000_000)).padStart(6, "0");
  }

  /** Empreinte tokenisée (SHA-256) pour les jetons stockés (refresh token, invitation). */
  tokenHash(token: string): Buffer {
    return sha256(token);
  }

  private hmac(key: string, data: string): Buffer {
    return createHmac("sha256", key).update(data).digest();
  }

  /** IP et appareil ne sont jamais stockés en clair : HMAC avec poivre serveur. */
  ipHash(ip: string | undefined): Buffer | null {
    return ip ? this.hmac(this.cfg.hmacPepper, `ip:${ip}`) : null;
  }
  deviceHash(deviceId: string | undefined): Buffer | null {
    return deviceId ? this.hmac(this.cfg.hmacPepper, `dev:${deviceId}`) : null;
  }
  otpHash(phone: string, purpose: string, code: string): Buffer {
    return this.hmac(this.cfg.hmacPepper, `otp:${phone}:${purpose}:${code}`);
  }
}
