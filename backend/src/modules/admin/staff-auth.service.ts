import { Inject, Injectable } from "@nestjs/common";
import { CONFIG, type AppConfig } from "../../kernel/config/config.js";
import { AppError, conflict, forbidden, unauthorized } from "../../kernel/errors.js";
import { AppLogger } from "../../kernel/logger.js";
import { CryptoService } from "../../kernel/security/crypto.service.js";
import { AdminDb, auditStaff } from "./admin-db.service.js";
import {
  decryptSecret,
  encryptSecret,
  generateTotpSecret,
  otpauthUri,
  base32Encode,
  verifyTotp,
} from "./totp.js";

export interface StaffPrincipal {
  staffId: string;
  sessionId: string;
  email: string;
  fullName: string;
  roles: string[];
  permissions: Set<string>;
  /** false : mot de passe vérifié, double authentification encore attendue. */
  mfaVerified: boolean;
  /** true : la double authentification n'est pas encore activée (enrôlement obligatoire). */
  mfaEnrollmentRequired: boolean;
  csrfHash: Buffer;
}

interface StaffRow {
  id: string;
  email: string;
  fullName: string;
  passwordHash: string;
  status: "ACTIVE" | "SUSPENDED";
  totpSecretEnc: Buffer | null;
  totpEnabledAt: Date | null;
  totpLastStep: number | null;
  failedLoginCount: number;
  lockedUntil: Date | null;
}

export interface IssuedSession {
  sessionToken: string;
  csrfToken: string;
  /** Étape suivante : activer la double authentification, ou saisir le code. */
  next: "enroll_totp" | "verify_totp";
}

const LOCKED = () =>
  new AppError(
    "STAFF_LOCKED",
    423,
    "Compte verrouillé après plusieurs échecs. Réessayez plus tard.",
  );

/**
 * Authentification du staff (docs/blueprint/09-admin.md §2, §6) : e-mail + mot de passe (argon2id),
 * puis double authentification TOTP OBLIGATOIRE ; session opaque courte (cookie HttpOnly) avec jeton
 * anti-CSRF ; verrouillage après échecs répétés ; tout est audité.
 */
@Injectable()
export class StaffAuthService {
  constructor(
    private readonly db: AdminDb,
    private readonly crypto: CryptoService,
    private readonly logger: AppLogger,
    @Inject(CONFIG) private readonly cfg: AppConfig,
  ) {}

  private loadStaffByEmail(email: string) {
    return this.db.one<StaffRow>(
      `SELECT id, email, full_name, password_hash, status, totp_secret_enc, totp_enabled_at,
              totp_last_step, failed_login_count, locked_until
         FROM core.staff_users WHERE email = $1`,
      [email.trim().toLowerCase()],
    );
  }

  private loadStaff(id: string) {
    return this.db.one<StaffRow>(
      `SELECT id, email, full_name, password_hash, status, totp_secret_enc, totp_enabled_at,
              totp_last_step, failed_login_count, locked_until
         FROM core.staff_users WHERE id = $1`,
      [id],
    );
  }

  private isLocked(staff: StaffRow) {
    return staff.lockedUntil !== null && staff.lockedUntil > new Date();
  }

  /** Un échec de plus ; au seuil, verrouillage (et remise à zéro du compteur). */
  private async recordFailure(staff: StaffRow, reason: string, ipHash: Buffer | null) {
    const count = staff.failedLoginCount + 1;
    const lock = count >= this.cfg.admin.maxFailedLogins;
    await this.db.query(
      `UPDATE core.staff_users
          SET failed_login_count = $2,
              locked_until = CASE WHEN $3::boolean THEN now() + make_interval(mins => $4) ELSE locked_until END
        WHERE id = $1`,
      [staff.id, lock ? 0 : count, lock, this.cfg.admin.lockMinutes],
    );
    await auditStaff(this.db, {
      staffId: staff.id,
      action: lock ? "staff.locked" : "staff.login_failed",
      targetType: "staff",
      targetId: staff.id,
      ipHash,
      metadata: { reason },
    });
  }

  async login(
    email: string,
    password: string,
    meta: { ip?: string; userAgent?: string },
  ): Promise<IssuedSession> {
    const ipHash = this.crypto.ipHash(meta.ip);
    const staff = await this.loadStaffByEmail(email);
    if (!staff) {
      await this.crypto.verifyDummy(password); // même durée qu'un vrai compte : pas d'oracle
      throw unauthorized("STAFF_INVALID_CREDENTIALS", "E-mail ou mot de passe incorrect");
    }
    if (this.isLocked(staff)) throw LOCKED();
    if (!(await this.crypto.verifyPassword(staff.passwordHash, password))) {
      await this.recordFailure(staff, "password", ipHash);
      throw unauthorized("STAFF_INVALID_CREDENTIALS", "E-mail ou mot de passe incorrect");
    }
    if (staff.status !== "ACTIVE") throw forbidden("STAFF_DISABLED", "Compte staff désactivé");

    const sessionToken = this.crypto.randomToken();
    const csrfToken = this.crypto.randomToken();
    await this.db.query(
      `INSERT INTO core.staff_sessions (staff_id, token_hash, csrf_hash, ip_hash, user_agent, expires_at)
       VALUES ($1, $2, $3, $4, $5, now() + make_interval(hours => $6))`,
      [
        staff.id,
        this.crypto.tokenHash(sessionToken),
        this.crypto.tokenHash(csrfToken),
        ipHash,
        meta.userAgent ?? null,
        this.cfg.admin.sessionMaxHours,
      ],
    );
    return {
      sessionToken,
      csrfToken,
      next: staff.totpEnabledAt ? "verify_totp" : "enroll_totp",
    };
  }

  /** Session valide (non révoquée, ni expirée, ni inactive trop longtemps), rafraîchie à l'usage. */
  async authenticate(sessionToken: string): Promise<StaffPrincipal | null> {
    const row = await this.db.one<{
      sessionId: string;
      staffId: string;
      email: string;
      fullName: string;
      status: string;
      mfaVerifiedAt: Date | null;
      totpEnabledAt: Date | null;
      csrfHash: Buffer;
    }>(
      `UPDATE core.staff_sessions s SET last_seen_at = now()
         FROM core.staff_users u
        WHERE s.token_hash = $1 AND u.id = s.staff_id
          AND s.revoked_at IS NULL AND s.expires_at > now()
          AND s.last_seen_at > now() - make_interval(mins => $2)
       RETURNING s.id AS session_id, u.id AS staff_id, u.email, u.full_name, u.status,
                 s.mfa_verified_at, u.totp_enabled_at, s.csrf_hash`,
      [this.crypto.tokenHash(sessionToken), this.cfg.admin.sessionIdleMinutes],
    );
    if (row?.status !== "ACTIVE") return null;
    const grants = await this.db.query<{ role: string; permission: string | null }>(
      `SELECT r.code AS role, p.code AS permission
         FROM core.staff_role_assignments a
         JOIN core.roles r ON r.id = a.role_id AND r.scope = 'PLATFORM'
         LEFT JOIN core.role_permissions rp ON rp.role_id = r.id
         LEFT JOIN core.permissions p ON p.id = rp.permission_id
        WHERE a.staff_id = $1`,
      [row.staffId],
    );
    return {
      staffId: row.staffId,
      sessionId: row.sessionId,
      email: row.email,
      fullName: row.fullName,
      roles: [...new Set(grants.rows.map((g) => g.role))].sort(),
      permissions: new Set(grants.rows.flatMap((g) => (g.permission ? [g.permission] : []))),
      mfaVerified: row.mfaVerifiedAt !== null,
      mfaEnrollmentRequired: row.totpEnabledAt === null,
      csrfHash: row.csrfHash,
    };
  }

  /** Enrôlement : nouveau secret (pas encore actif tant qu'un premier code n'est pas validé). */
  async setupTotp(principal: StaffPrincipal): Promise<{ otpauthUri: string; secret: string }> {
    if (!principal.mfaEnrollmentRequired)
      throw conflict("TOTP_ALREADY_ENABLED", "La double authentification est déjà activée");
    const secret = generateTotpSecret();
    await this.db.query("UPDATE core.staff_users SET totp_secret_enc = $2 WHERE id = $1", [
      principal.staffId,
      encryptSecret(this.cfg.admin.totpKey, secret),
    ]);
    return { otpauthUri: otpauthUri(secret, principal.email), secret: base32Encode(secret) };
  }

  /**
   * Premier code (enrôlement) ou code de connexion : valide la session. Un code faux compte comme
   * un échec de connexion (verrouillage au seuil).
   */
  async confirmTotp(principal: StaffPrincipal, code: string, ipHash: Buffer | null) {
    const staff = await this.loadStaff(principal.staffId);
    if (!staff) throw unauthorized();
    if (this.isLocked(staff)) throw LOCKED();
    if (!staff.totpSecretEnc)
      throw conflict("TOTP_NOT_SET_UP", "Commencez par configurer la double authentification");
    const enrolling = staff.totpEnabledAt === null;
    const step = verifyTotp(
      decryptSecret(this.cfg.admin.totpKey, staff.totpSecretEnc),
      code,
      Date.now(),
      staff.totpLastStep,
    );
    if (step === null) {
      await this.recordFailure(staff, "totp", ipHash);
      throw unauthorized("STAFF_INVALID_TOTP", "Code de vérification incorrect");
    }
    await this.db.tx(async (tx) => {
      await tx.query(
        `UPDATE core.staff_users
            SET totp_last_step = $2, totp_enabled_at = COALESCE(totp_enabled_at, now()),
                failed_login_count = 0, locked_until = NULL, last_login_at = now()
          WHERE id = $1`,
        [staff.id, step],
      );
      await tx.query("UPDATE core.staff_sessions SET mfa_verified_at = now() WHERE id = $1", [
        principal.sessionId,
      ]);
      if (enrolling)
        await auditStaff(tx, {
          staffId: staff.id,
          action: "staff.totp_enabled",
          targetType: "staff",
          targetId: staff.id,
          ipHash,
        });
      await auditStaff(tx, {
        staffId: staff.id,
        action: "staff.login",
        targetType: "staff",
        targetId: staff.id,
        ipHash,
        metadata: { roles: principal.roles },
      });
    });
    // Connexion d'un super-administrateur : usage exceptionnel, signalée à chaque fois.
    if (principal.roles.includes("SUPER_ADMIN"))
      this.logger.warn(`admin: connexion SUPER_ADMIN (${principal.staffId})`, "security");
  }

  /**
   * Nouveau jeton anti-CSRF pour la session (l'ancien cesse de valoir). L'app d'admin le demande à
   * chaque chargement : seule une page de la même origine peut lire cette réponse.
   */
  async rotateCsrf(principal: StaffPrincipal): Promise<string> {
    const csrfToken = this.crypto.randomToken();
    await this.db.query("UPDATE core.staff_sessions SET csrf_hash = $2 WHERE id = $1", [
      principal.sessionId,
      this.crypto.tokenHash(csrfToken),
    ]);
    return csrfToken;
  }

  async logout(principal: StaffPrincipal): Promise<void> {
    await this.db.tx(async (tx) => {
      await tx.query("UPDATE core.staff_sessions SET revoked_at = now() WHERE id = $1", [
        principal.sessionId,
      ]);
      await auditStaff(tx, {
        staffId: principal.staffId,
        action: "staff.logout",
        targetType: "staff",
        targetId: principal.staffId,
      });
    });
  }
}
