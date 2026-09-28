import { Inject, Injectable } from "@nestjs/common";
import { Db, type Tx } from "../../kernel/db/db.service.js";
import { badRequest, notFound } from "../../kernel/errors.js";
import { AppLogger } from "../../kernel/logger.js";
import { PUSH_SENDER, type PushSenderPort } from "../../kernel/notifications/push-sender.port.js";
import { clampLimit, decodeCursor, encodeCursor, type Page } from "../../kernel/util.js";
import {
  NOTIFICATION_TYPES,
  isNotificationType,
  type Locale,
  type NotificationType,
} from "./notification-types.js";

export interface NotifyInput {
  userId: string;
  type: NotificationType;
  /** Valeurs des gabarits ET données de routage renvoyées à l'app (chaînes seulement). */
  data: Record<string, string>;
  businessId?: string | null;
  /** Anti-doublon : un même (utilisateur, clé) ne produit jamais deux notifications. */
  dedupeKey?: string;
}

export interface NotificationView {
  id: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, string>;
  businessId: string | null;
  readAt: Date | null;
  createdAt: Date;
}

const VIEW_COLUMNS = `id, type, title, body, data, business_id, read_at, created_at`;

/**
 * Moteur de notifications (docs/blueprint/06-platform-engines.md §2) : boîte de réception in-app
 * (toujours), push FCM (selon préférences et appareils enregistrés), état de livraison par canal.
 * Toutes les lectures/écritures `ntf.*` passent sous RLS avec `app.user_id` = destinataire.
 */
@Injectable()
export class NotificationsService {
  constructor(
    private readonly db: Db,
    private readonly logger: AppLogger,
    @Inject(PUSH_SENDER) private readonly push: PushSenderPort,
  ) {}

  /** Crée (au plus une fois par `dedupeKey`) et livre une notification. Renvoie son id, ou null si doublon. */
  async notify(input: NotifyInput): Promise<string | null> {
    const template = NOTIFICATION_TYPES[input.type];
    const created = await this.db.withTenant({ userId: input.userId }, async (tx) => {
      const user = await this.db.one<{ locale: string; status: string }>(
        "SELECT locale, status FROM core.users WHERE id = $1",
        [input.userId],
        tx,
      );
      if (!user || user.status === "DELETED") return null;
      const locale: Locale = user.locale === "en" ? "en" : "fr";
      const { title, body } = template.render(locale, input.data);
      const data = { ...input.data, type: input.type };

      const inserted = await this.db.one<{ id: string }>(
        `INSERT INTO ntf.notifications (user_id, business_id, type, title, body, data, dedupe_key)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (user_id, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
         RETURNING id`,
        [
          input.userId,
          input.businessId ?? null,
          input.type,
          title,
          body,
          JSON.stringify(data),
          input.dedupeKey ?? null,
        ],
        tx,
      );
      if (!inserted) return null;
      await tx.query(
        `INSERT INTO ntf.notification_deliveries (notification_id, user_id, channel, status, attempts)
         VALUES ($1, $2, 'IN_APP', 'SENT', 1)`,
        [inserted.id, input.userId],
      );

      const pushAllowed =
        (template.channels as readonly string[]).includes("PUSH") &&
        (!template.optional || (await this.pushEnabled(tx, input.userId, input.type)));
      const tokens = pushAllowed ? await this.activeTokens(tx, input.userId) : [];
      // Rien à pousser (préférence coupée, ou aucun appareil) : tranché ici, sans 2ᵉ transaction.
      const status = tokens.length > 0 ? "PENDING" : "SKIPPED";
      const reason = pushAllowed ? "aucun appareil enregistré" : null;
      await tx.query(
        `INSERT INTO ntf.notification_deliveries (notification_id, user_id, channel, status, last_error)
         VALUES ($1, $2, 'PUSH', $3, $4)`,
        [inserted.id, input.userId, status, status === "SKIPPED" ? reason : null],
      );
      return { id: inserted.id, title, body, data, tokens };
    });
    if (!created) return null;
    if (created.tokens.length > 0) await this.deliverPush(input.userId, created);
    return created.id;
  }

  private async pushEnabled(tx: Tx, userId: string, type: string): Promise<boolean> {
    const pref = await this.db.one<{ enabled: boolean }>(
      `SELECT enabled FROM ntf.notification_preferences WHERE user_id = $1 AND type = $2 AND channel = 'PUSH'`,
      [userId, type],
      tx,
    );
    return pref?.enabled ?? true;
  }

  /**
   * Push « au mieux » : un échec du fournisseur est ENREGISTRÉ (statut FAILED, visible), jamais
   * propagé — la notification in-app existe déjà, et rejouer l'événement ne la recréerait pas.
   */
  private async activeTokens(tx: Tx, userId: string): Promise<string[]> {
    const r = await tx.query<{ token: string }>(
      "SELECT token FROM ntf.device_tokens WHERE user_id = $1 AND revoked_at IS NULL",
      [userId],
    );
    return r.rows.map((row) => row.token);
  }

  /**
   * Push « au mieux », HORS de la transaction qui a créé la notification (un appel réseau ne doit
   * jamais garder une transaction ouverte). Un échec du fournisseur est ENREGISTRÉ (statut FAILED,
   * visible), jamais propagé — la notification in-app existe déjà, et rejouer l'événement ne la
   * recréerait pas.
   */
  private async deliverPush(
    userId: string,
    n: { id: string; title: string; body: string; data: Record<string, string>; tokens: string[] },
  ): Promise<void> {
    let status = "SENT";
    let error: string | null = null;
    let invalid: string[] = [];
    try {
      const result = await this.push.send(n.tokens, {
        title: n.title,
        body: n.body,
        data: { ...n.data, notificationId: n.id },
      });
      invalid = result.invalidTokens;
    } catch (e) {
      status = "FAILED";
      error = (e instanceof Error ? e.message : String(e)).slice(0, 300);
      this.logger.warn(`push: échec pour la notification ${n.id} : ${error}`, "notifications");
    }
    await this.db.withTenant({ userId }, async (tx) => {
      if (invalid.length > 0)
        await tx.query(
          "UPDATE ntf.device_tokens SET revoked_at = now() WHERE user_id = $1 AND token = ANY($2)",
          [userId, invalid],
        );
      await this.setPushStatus(tx, n.id, status, error);
    });
  }

  private async setPushStatus(
    tx: Tx,
    notificationId: string,
    status: string,
    error: string | null,
  ) {
    await tx.query(
      `UPDATE ntf.notification_deliveries
          SET status = $2, last_error = $3, attempts = attempts + 1, updated_at = now()
        WHERE notification_id = $1 AND channel = 'PUSH'`,
      [notificationId, status, error],
    );
  }

  // ─── Boîte de réception ───

  async list(userId: string, limit?: number, cursor?: string): Promise<Page<NotificationView>> {
    const n = clampLimit(limit, 20, 50);
    const after = decodeCursor<{ c: string; i: string }>(cursor);
    const rows = await this.db.withTenant({ userId }, (tx) =>
      tx.query<NotificationView>(
        `SELECT ${VIEW_COLUMNS} FROM ntf.notifications
          WHERE user_id = $1 ${after ? "AND (created_at, id) < ($3::timestamptz, $4::uuid)" : ""}
          ORDER BY created_at DESC, id DESC
          LIMIT $2`,
        after ? [userId, n + 1, after.c, after.i] : [userId, n + 1],
      ),
    );
    const items = rows.rows.slice(0, n);
    const last = items.at(-1);
    return {
      items,
      nextCursor:
        rows.rows.length > n && last
          ? encodeCursor({ c: new Date(last.createdAt).toISOString(), i: last.id })
          : null,
    };
  }

  async unreadCount(userId: string): Promise<{ unread: number }> {
    const row = await this.db.withTenant({ userId }, (tx) =>
      this.db.one<{ unread: number }>(
        "SELECT count(*)::int AS unread FROM ntf.notifications WHERE user_id = $1 AND read_at IS NULL",
        [userId],
        tx,
      ),
    );
    return { unread: row?.unread ?? 0 };
  }

  async markRead(userId: string, id: string): Promise<NotificationView> {
    const row = await this.db.withTenant({ userId }, (tx) =>
      this.db.one<NotificationView>(
        `UPDATE ntf.notifications SET read_at = COALESCE(read_at, now())
          WHERE id = $1 AND user_id = $2 RETURNING ${VIEW_COLUMNS}`,
        [id, userId],
        tx,
      ),
    );
    if (!row) throw notFound();
    return row;
  }

  async markAllRead(userId: string): Promise<{ updated: number }> {
    const r = await this.db.withTenant({ userId }, (tx) =>
      tx.query(
        "UPDATE ntf.notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL",
        [userId],
      ),
    );
    return { updated: r.rowCount };
  }

  // ─── Préférences (push seulement : la boîte in-app garde toujours une trace) ───

  async preferences(userId: string) {
    const rows = await this.db.withTenant({ userId }, (tx) =>
      tx.query<{ type: string; enabled: boolean }>(
        `SELECT type, enabled FROM ntf.notification_preferences WHERE user_id = $1 AND channel = 'PUSH'`,
        [userId],
      ),
    );
    const saved = new Map(rows.rows.map((r) => [r.type, r.enabled]));
    return Object.entries(NOTIFICATION_TYPES)
      .filter(([, tpl]) => tpl.optional && (tpl.channels as readonly string[]).includes("PUSH"))
      .map(([type]) => ({ type, push: saved.get(type) ?? true }));
  }

  async setPreferences(userId: string, push: Record<string, boolean>) {
    for (const [type, enabled] of Object.entries(push)) {
      if (!isNotificationType(type))
        throw badRequest("UNKNOWN_NOTIFICATION_TYPE", `Type inconnu : ${type}`);
      if (typeof enabled !== "boolean")
        throw badRequest("INVALID_PREFERENCE", `La valeur de « ${type} » doit être true ou false.`);
      if (!NOTIFICATION_TYPES[type].optional)
        throw badRequest("NOTIFICATION_MANDATORY", `« ${type} » ne peut pas être désactivée.`);
    }
    await this.db.withTenant({ userId }, async (tx) => {
      for (const [type, enabled] of Object.entries(push)) {
        await tx.query(
          `INSERT INTO ntf.notification_preferences (user_id, type, channel, enabled)
           VALUES ($1, $2, 'PUSH', $3)
           ON CONFLICT (user_id, type, channel) DO UPDATE SET enabled = EXCLUDED.enabled`,
          [userId, type, enabled],
        );
      }
    });
    return this.preferences(userId);
  }

  // ─── Appareils (jetons FCM) ───

  /**
   * Enregistre le jeton de CET appareil pour l'utilisateur. Si un autre compte s'était connecté sur
   * le même téléphone, il cesse d'y recevoir ses notifications (politique `token_holder_release`).
   */
  async registerDevice(userId: string, token: string, platform: string): Promise<void> {
    await this.db.tx(async (tx) => {
      await tx.query("SELECT set_config('app.user_id', $1, true)", [userId]);
      await tx.query("SELECT set_config('app.device_token', $1, true)", [token]);
      await tx.query("DELETE FROM ntf.device_tokens WHERE token = $1 AND user_id <> $2", [
        token,
        userId,
      ]);
      await tx.query(
        `INSERT INTO ntf.device_tokens (user_id, token, platform) VALUES ($1, $2, $3)
         ON CONFLICT (token) DO UPDATE SET platform = EXCLUDED.platform, last_seen_at = now(), revoked_at = NULL`,
        [userId, token, platform],
      );
    });
  }

  async unregisterDevice(userId: string, token: string): Promise<void> {
    await this.db.withTenant({ userId }, (tx) =>
      tx.query("DELETE FROM ntf.device_tokens WHERE user_id = $1 AND token = $2", [userId, token]),
    );
  }
}
