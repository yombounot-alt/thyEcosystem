import type { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import pg from "pg";
import request from "supertest";
import { AppModule } from "../src/app.module.js";
import { configureApp } from "../src/bootstrap.js";
import { CONFIG, type AppConfig } from "../src/kernel/config/config.js";
import { OutboxRelayService } from "../src/kernel/events/outbox-relay.service.js";
import { PUSH_SENDER, type PushMessage } from "../src/kernel/notifications/push-sender.port.js";
import { SMS_SENDER } from "../src/kernel/notifications/sms-sender.port.js";
import {
  ERROR_REPORTER,
  type ErrorContext,
} from "../src/kernel/observability/error-reporter.port.js";
import { RedisService } from "../src/kernel/redis/redis.service.js";

export const API = "/api/v1";

export interface Harness {
  app: INestApplication;
  server: ReturnType<INestApplication["getHttpServer"]>;
  cfg: AppConfig;
  /** Dernier code OTP « envoyé » à ce numéro (l'adaptateur SMS est remplacé par une capture). */
  otpFor(phone: string): string;
  /** SMS texte « envoyés » (invitations…), par numéro. */
  smsTo(phone: string): string[];
  /** Push « envoyés » : jetons visés et message. */
  pushes: { tokens: string[]; message: PushMessage }[];
  /** Erreurs remontées (à Sentry en production) pendant la suite. */
  reportedErrors: { error: unknown; context?: ErrorContext }[];
  /** Fait tourner le relais d'outbox jusqu'à épuisement (il n'a pas de minuterie en test). */
  drainOutbox(): Promise<void>;
  /**
   * Considère comme déjà traités les événements laissés par les AUTRES suites (base partagée) :
   * une suite qui observe le relais ne dépend ainsi que de ses propres événements.
   */
  skipOutboxBacklog(): Promise<void>;
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
  const texts = new Map<string, string[]>();
  const pushes: { tokens: string[]; message: PushMessage }[] = [];
  const reportedErrors: { error: unknown; context?: ErrorContext }[] = [];
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(SMS_SENDER)
    .useValue({
      sendOtp(phone: string, code: string) {
        codes.set(phone, code);
        return Promise.resolve();
      },
      sendText(phone: string, text: string) {
        texts.set(phone, [...(texts.get(phone) ?? []), text]);
        return Promise.resolve();
      },
    })
    .overrideProvider(ERROR_REPORTER)
    .useValue({
      capture(error: unknown, context?: ErrorContext) {
        reportedErrors.push({ error, context });
      },
      flush: () => Promise.resolve(),
    })
    .overrideProvider(PUSH_SENDER)
    .useValue({
      send(tokens: string[], message: PushMessage) {
        pushes.push({ tokens, message });
        return Promise.resolve({ invalidTokens: tokens.filter((t) => t.startsWith("invalid-")) });
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
    smsTo(phone) {
      return texts.get(phone) ?? [];
    },
    pushes,
    reportedErrors,
    async drainOutbox() {
      const relay = app.get(OutboxRelayService);
      while ((await relay.drain(500)) > 0) {
        /* jusqu'à épuisement */
      }
    },
    async skipOutboxBacklog() {
      await sql.query(
        "UPDATE ops.outbox_events SET published_at = now() WHERE published_at IS NULL AND failed_at IS NULL",
      );
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

/**
 * Crée une entreprise dont `session` est propriétaire ; renvoie le jeton d'accès avec l'entreprise
 * active. Par défaut, les limites de l'offre gratuite sont levées (dérogation, comme le ferait le
 * support) : les suites métier créent bien plus de produits et de membres qu'un vrai commerçant
 * « découverte ». `freePlan: true` garde les limites réelles (suite abonnements).
 */
export async function createBusiness(
  h: Harness,
  session: Session,
  name: string,
  opts: { freePlan?: boolean } = {},
) {
  const res = await request(h.server)
    .post(`${API}/businesses`)
    .set("Authorization", `Bearer ${session.accessToken}`)
    .send({ name, businessType: "commerce" })
    .expect(201);
  const businessId = res.body.business.id as string;
  if (!opts.freePlan) await liftPlanLimits(h, businessId);
  return { accessToken: res.body.accessToken as string, businessId };
}

/** Dérogation « illimité » sur les limites de l'offre (membres, produits). */
export async function liftPlanLimits(h: Harness, businessId: string): Promise<void> {
  await h.sql.query(
    `INSERT INTO sub.entitlement_overrides (business_id, entitlement_code, value, reason)
     SELECT $1, code, NULL, 'tests' FROM sub.entitlements WHERE kind = 'LIMIT'
     ON CONFLICT (business_id, entitlement_code) DO UPDATE SET value = NULL`,
    [businessId],
  );
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
