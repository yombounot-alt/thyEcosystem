import { Inject, Injectable } from "@nestjs/common";
import { CONFIG, type AppConfig } from "../../kernel/config/config.js";
import { Db } from "../../kernel/db/db.service.js";
import { tooMany, unprocessable } from "../../kernel/errors.js";
import { SMS_SENDER, type SmsSenderPort } from "../../kernel/notifications/sms-sender.port.js";
import { CryptoService, safeEqual } from "../../kernel/security/crypto.service.js";

const PURPOSE = "LOGIN_OR_REGISTER";
const OTP_TTL_MIN = 10;
const MAX_ATTEMPTS = 5;
const MAX_PER_10_MIN = 3;
const MAX_PER_DAY = 10;

/**
 * OTP téléphone, indépendant de tout compte tant qu'il n'est pas vérifié — inscription et connexion
 * sont le MÊME flux (docs/blueprint/04-identity-access.md §2.2) : `verify()` ne crée/retrouve le
 * compte que si le code est bon (voir AuthService.otpVerify).
 */
@Injectable()
export class OtpService {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    @Inject(SMS_SENDER) private readonly sms: SmsSenderPort,
    @Inject(CONFIG) private readonly cfg: AppConfig,
  ) {}

  async request(phone: string): Promise<void> {
    const counts = await this.db.one<{ recent: number; day: number }>(
      `SELECT count(*) FILTER (WHERE created_at > now() - interval '10 minutes')::int AS recent,
              count(*) FILTER (WHERE created_at > now() - interval '1 day')::int AS day
         FROM core.otp_challenges WHERE phone = $1 AND purpose = $2`,
      [phone, PURPOSE],
    );
    if ((counts?.recent ?? 0) >= MAX_PER_10_MIN || (counts?.day ?? 0) >= MAX_PER_DAY) {
      throw tooMany("OTP_RATE_LIMITED", "Trop de codes demandés, réessayez plus tard", 600);
    }

    const code = this.cfg.sms.fixedOtp ?? this.crypto.randomOtp();
    await this.db.tx(async (tx) => {
      await tx.query(
        `UPDATE core.otp_challenges SET consumed_at = now() WHERE phone = $1 AND purpose = $2 AND consumed_at IS NULL`,
        [phone, PURPOSE],
      );
      await tx.query(
        `INSERT INTO core.otp_challenges (phone, purpose, code_hash, expires_at) VALUES ($1, $2, $3, now() + make_interval(mins => $4))`,
        [phone, PURPOSE, this.crypto.otpHash(phone, PURPOSE, code), OTP_TTL_MIN],
      );
    });
    await this.sms.sendOtp(phone, code);
  }

  /** 5 essais max, expiration, usage unique, comparaison à temps constant. */
  async verify(phone: string, code: string): Promise<void> {
    const row = await this.db.one<{ id: string; codeHash: Buffer; attempts: number }>(
      `SELECT id, code_hash, attempts FROM core.otp_challenges
        WHERE phone = $1 AND purpose = $2 AND consumed_at IS NULL AND expires_at > now()
        ORDER BY created_at DESC LIMIT 1`,
      [phone, PURPOSE],
    );
    if (!row) throw unprocessable("OTP_INVALID", "Code invalide ou expiré");
    // Incrément atomique AVANT la comparaison : pas de course permettant plus de 5 essais.
    const bumped = await this.db.one<{ attempts: number }>(
      `UPDATE core.otp_challenges SET attempts = attempts + 1 WHERE id = $1 AND attempts < $2 RETURNING attempts`,
      [row.id, MAX_ATTEMPTS],
    );
    if (!bumped)
      throw unprocessable("OTP_TOO_MANY_ATTEMPTS", "Trop d'essais, demandez un nouveau code");
    if (!safeEqual(row.codeHash, this.crypto.otpHash(phone, PURPOSE, code)))
      throw unprocessable("OTP_INVALID", "Code invalide ou expiré");
    await this.db.query("UPDATE core.otp_challenges SET consumed_at = now() WHERE id = $1", [
      row.id,
    ]);
  }
}
