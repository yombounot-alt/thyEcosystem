import { createCipheriv, createDecipheriv, createHmac, randomBytes } from "node:crypto";
import { safeEqual } from "../../kernel/security/crypto.service.js";

/**
 * Double authentification du staff : TOTP (RFC 6238, HMAC-SHA1, 6 chiffres, pas de 30 s) —
 * compatible Google Authenticator, Authy, 1Password… Implémenté avec `node:crypto` seul.
 */
export const TOTP_PERIOD_SEC = 30;
export const TOTP_DIGITS = 6;
/** Tolérance d'horloge : le pas courant et ±1 (±30 s). */
const WINDOW = 1;

const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function base32Encode(buf: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = "";
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32.charAt((value >>> (bits - 5)) & 31);
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32.charAt((value << (5 - bits)) & 31);
  return out;
}

export function base32Decode(text: string): Buffer {
  const clean = text.toUpperCase().replace(/=+$/, "");
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const char of clean) {
    const index = BASE32.indexOf(char);
    if (index < 0) throw new Error("base32 invalide");
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

/** Secret de 160 bits (recommandation RFC 4226). */
export function generateTotpSecret(): Buffer {
  return randomBytes(20);
}

/** Code HOTP (RFC 4226) pour un compteur donné, sur `digits` chiffres. */
export function hotp(secret: Buffer, counter: number, digits = TOTP_DIGITS): string {
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(counter));
  const mac = createHmac("sha1", secret).update(msg).digest();
  const offset = mac.readUInt8(mac.length - 1) & 0x0f;
  const binary = mac.readUInt32BE(offset) & 0x7fffffff;
  return String(binary % 10 ** digits).padStart(digits, "0");
}

export const totpStep = (nowMs: number) => Math.floor(nowMs / 1000 / TOTP_PERIOD_SEC);

/**
 * Vérifie un code : renvoie le pas de temps accepté, ou null. `lastStep` = dernier pas déjà utilisé
 * par ce compte : un code rejoué (même pas ou antérieur) est refusé, même s'il est encore valable.
 */
export function verifyTotp(
  secret: Buffer,
  code: string,
  nowMs: number,
  lastStep: number | null,
): number | null {
  if (!/^\d{6}$/.test(code)) return null;
  const current = totpStep(nowMs);
  for (let delta = -WINDOW; delta <= WINDOW; delta++) {
    const step = current + delta;
    if (lastStep !== null && step <= lastStep) continue;
    if (safeEqual(Buffer.from(hotp(secret, step)), Buffer.from(code))) return step;
  }
  return null;
}

/** URI d'enrôlement (QR code dans l'application d'authentification). */
export function otpauthUri(secret: Buffer, account: string, issuer = "THY Admin"): string {
  const label = encodeURIComponent(`${issuer}:${account}`);
  const params = new URLSearchParams({
    secret: base32Encode(secret),
    issuer,
    algorithm: "SHA1",
    digits: String(TOTP_DIGITS),
    period: String(TOTP_PERIOD_SEC),
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}

// ─── Secret au repos : AES-256-GCM (iv 12 octets | tag 16 octets | chiffré) ─────────────────────

export function encryptSecret(key: Buffer, secret: Buffer): Buffer {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const enc = Buffer.concat([cipher.update(secret), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), enc]);
}

export function decryptSecret(key: Buffer, blob: Buffer): Buffer {
  const decipher = createDecipheriv("aes-256-gcm", key, blob.subarray(0, 12));
  decipher.setAuthTag(blob.subarray(12, 28));
  return Buffer.concat([decipher.update(blob.subarray(28)), decipher.final()]);
}
