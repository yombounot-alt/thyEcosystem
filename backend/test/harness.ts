import type { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import pg from "pg";
import request from "supertest";
import { AppModule } from "../src/app.module.js";
import { configureApp } from "../src/bootstrap.js";
import { CONFIG, type AppConfig } from "../src/kernel/config/config.js";
import { SMS_SENDER } from "../src/kernel/notifications/sms-sender.port.js";
import { RedisService } from "../src/kernel/redis/redis.service.js";

export const API = "/api/v1";

export interface Harness {
  app: INestApplication;
  server: ReturnType<INestApplication["getHttpServer"]>;
  cfg: AppConfig;
  /** Dernier code OTP « envoyé » à ce numéro (l'adaptateur SMS est remplacé par une capture). */
  otpFor(phone: string): string;
  /**
   * Accès SQL direct sous le rôle propriétaire du schéma (contourne la RLS) : sert à préparer un
   * état ou à vérifier ce que l'API ne montre pas. Jamais utilisé pour éviter l'API dans un test
   * de comportement.
   */
  sql: pg.Pool;
  close(): Promise<void>;
}

export interface HarnessOptions {
  /** Réactive la limitation de débit (désactivée par défaut dans les tests, voir setup-env.ts). */
  rateLimit?: boolean;
}

export async function createHarness(opts: HarnessOptions = {}): Promise<Harness> {
  if (opts.rateLimit !== undefined) process.env.RATE_LIMIT_ENABLED = String(opts.rateLimit);
  const codes = new Map<string, string>();
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(SMS_SENDER)
    .useValue({
      async sendOtp(phone: string, code: string) {
        codes.set(phone, code);
      },
    })
    .compile();

  // bodyParser: false comme en production : configureApp installe son propre parseur JSON.
  const app = moduleRef.createNestApplication({ bodyParser: false });
  const cfg = app.get<AppConfig>(CONFIG);
  configureApp(app, cfg);
  await app.init();
  await redisReady(app.get(RedisService));

  const sql = new pg.Pool({ connectionString: cfg.migratorDatabaseUrl, max: 2 });
  return {
    app,
    server: app.getHttpServer(),
    cfg,
    otpFor(phone) {
      const code = codes.get(phone);
      if (!code) throw new Error(`Aucun OTP capturé pour ${phone}`);
      return code;
    },
    sql,
    async close() {
      await sql.end();
      await app.close();
    },
  };
}

/**
 * Le client Redis se connecte en arrière-plan (file hors-ligne désactivée) : une requête tirée
 * avant la fin de la connexion échouerait en « fail-closed » (503). On attend donc qu'il réponde.
 */
async function redisReady(redis: RedisService): Promise<void> {
  for (let i = 0; i < 50; i++) {
    if (await redis.ping()) return;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("Redis injoignable pour les tests (docker compose up ?)");
}

let phoneSeq = 0;
/** Numéro E.164 guinéen unique par exécution : aucune donnée à nettoyer entre deux passes. */
export function uniquePhone(): string {
  const body = `${Date.now()}${++phoneSeq}${Math.floor(Math.random() * 1000)}`.slice(-8);
  return `+2246${body}`;
}

export interface Session {
  accessToken: string;
  refreshToken: string;
  userId: string;
}

/** Inscription ou connexion par OTP (flux unique, ADR-004) — sans entreprise active. */
export async function loginWithOtp(h: Harness, phone: string): Promise<Session> {
  await request(h.server)
    .post(`${API}/auth/otp/request`)
    .send({ phone })
    .expect((r) => {
      if (r.status >= 300) throw new Error(`otp/request → ${r.status} ${JSON.stringify(r.body)}`);
    });
  const res = await request(h.server)
    .post(`${API}/auth/otp/verify`)
    .send({ phone, code: h.otpFor(phone) })
    .expect(200);
  return {
    accessToken: res.body.accessToken,
    refreshToken: res.body.refreshToken,
    userId: res.body.user.id,
  };
}

/** Crée une entreprise dont `session` est propriétaire ; renvoie le jeton d'accès avec l'entreprise active. */
export async function createBusiness(h: Harness, session: Session, name: string) {
  const res = await request(h.server)
    .post(`${API}/businesses`)
    .set("Authorization", `Bearer ${session.accessToken}`)
    .send({ name, businessType: "commerce" })
    .expect(201);
  return {
    accessToken: res.body.accessToken as string,
    businessId: res.body.business.id as string,
  };
}

/** Raccourci historique des suites thyBusiness : inscription + entreprise. */
export async function signupAndCreateBusiness(
  h: Harness,
  user: { phone: string },
  businessName: string,
) {
  const session = await loginWithOtp(h, user.phone);
  const business = await createBusiness(h, session, businessName);
  return {
    accessToken: business.accessToken,
    noBusinessToken: session.accessToken,
    businessId: business.businessId,
    userId: session.userId,
  };
}

/** Ajoute directement (SQL) un membre à une entreprise — l'API d'invitation a sa propre suite. */
export async function addMemberSql(
  h: Harness,
  businessId: string,
  userId: string,
  roleCode: string,
): Promise<void> {
  await h.sql.query(
    `INSERT INTO core.business_members (business_id, user_id, role_id)
     SELECT $1, $2, id FROM core.roles WHERE code = $3`,
    [businessId, userId, roleCode],
  );
}
