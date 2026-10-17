import { randomBytes } from "node:crypto";
import {
  base32Decode,
  base32Encode,
  decryptSecret,
  encryptSecret,
  hotp,
  otpauthUri,
  totpStep,
  verifyTotp,
} from "./totp.js";

// RFC 6238, annexe B : secret ASCII "12345678901234567890", HMAC-SHA1, 8 chiffres.
const RFC_SECRET = Buffer.from("12345678901234567890", "ascii");
const RFC_VECTORS: [number, string][] = [
  [59, "94287082"],
  [1111111109, "07081804"],
  [1111111111, "14050471"],
  [1234567890, "89005924"],
  [2000000000, "69279037"],
  [20000000000, "65353130"],
];

describe("TOTP (RFC 6238)", () => {
  it("reproduit les vecteurs de test officiels", () => {
    for (const [time, expected] of RFC_VECTORS) {
      expect(hotp(RFC_SECRET, Math.floor(time / 30), 8), `t=${time}`).toBe(expected);
    }
  });

  it("accepte le code courant et une dérive d'horloge de ±30 s, pas au-delà", () => {
    const now = 1_700_000_000_000;
    const step = totpStep(now);
    expect(verifyTotp(RFC_SECRET, hotp(RFC_SECRET, step), now, null)).toBe(step);
    expect(verifyTotp(RFC_SECRET, hotp(RFC_SECRET, step - 1), now, null)).toBe(step - 1);
    expect(verifyTotp(RFC_SECRET, hotp(RFC_SECRET, step + 1), now, null)).toBe(step + 1);
    expect(verifyTotp(RFC_SECRET, hotp(RFC_SECRET, step - 2), now, null)).toBeNull();
  });

  it("refuse un code rejoué (pas déjà utilisé) et les formats invalides", () => {
    const now = 1_700_000_000_000;
    const step = totpStep(now);
    const code = hotp(RFC_SECRET, step);
    expect(verifyTotp(RFC_SECRET, code, now, step)).toBeNull();
    expect(verifyTotp(RFC_SECRET, "12345", now, null)).toBeNull();
    expect(verifyTotp(RFC_SECRET, "abcdef", now, null)).toBeNull();
  });

  it("encode en base32 (RFC 4648) et produit une URI d'enrôlement standard", () => {
    expect(base32Encode(Buffer.from("foobar"))).toBe("MZXW6YTBOI");
    expect(base32Decode("MZXW6YTBOI").toString()).toBe("foobar");
    expect(base32Decode(base32Encode(RFC_SECRET)).equals(RFC_SECRET)).toBe(true);
    const uri = otpauthUri(RFC_SECRET, "awa@thy.test");
    expect(uri).toMatch(/^otpauth:\/\/totp\/THY%20Admin%3Aawa%40thy\.test\?/);
    expect(uri).toContain(`secret=${base32Encode(RFC_SECRET)}`);
    expect(uri).toContain("digits=6");
  });
});

describe("secret TOTP au repos (AES-256-GCM)", () => {
  it("chiffre et déchiffre ; une altération ou une autre clé est refusée", () => {
    const key = randomBytes(32);
    const secret = randomBytes(20);
    const blob = encryptSecret(key, secret);
    expect(decryptSecret(key, blob).equals(secret)).toBe(true);
    expect(blob.includes(secret)).toBe(false);

    const tampered = Buffer.from(blob);
    const lastByte = tampered.length - 1;
    tampered.writeUInt8(tampered.readUInt8(lastByte) ^ 1, lastByte);
    expect(() => decryptSecret(key, tampered)).toThrow();
    expect(() => decryptSecret(randomBytes(32), blob)).toThrow();
  });
});
