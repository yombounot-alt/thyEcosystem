-- Notifications (schéma `ntf`) + reprise sur erreur du relais d'outbox (ops.outbox_events).
-- Référence : docs/blueprint/06-platform-engines.md §2, docs/plans/phase-0-foundation.md L0.8.

-- ---------------------------------------------------------------------------
-- Relais d'outbox : bail, tentatives, file des morts
-- ---------------------------------------------------------------------------
-- `next_attempt_at` sert à la fois de BAIL (un relais qui réclame un événement le repousse d'une
-- minute : s'il plante, un autre le reprend) et de RETARD entre deux tentatives (backoff). Un
-- événement qui échoue trop de fois reçoit `failed_at` : c'est la file des morts — il n'est plus
-- rejoué, mais reste en table, visible et alertable (WHERE failed_at IS NOT NULL).
ALTER TABLE ops.outbox_events
  ADD COLUMN next_attempt_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN failed_at       timestamptz,
  ADD COLUMN last_error      text;

DROP INDEX ops.outbox_pending_idx;
CREATE INDEX outbox_ready_idx ON ops.outbox_events (next_attempt_at)
  WHERE published_at IS NULL AND failed_at IS NULL;
CREATE INDEX outbox_dead_idx ON ops.outbox_events (failed_at) WHERE failed_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Schéma ntf
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS ntf;
GRANT USAGE ON SCHEMA ntf TO thy_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA ntf GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO thy_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA ntf GRANT USAGE, SELECT ON SEQUENCES TO thy_app;

-- Boîte de réception. Le titre et le corps sont rendus à la création, dans la langue de
-- l'utilisateur à ce moment-là : une notification est un fait historique, pas une vue.
CREATE TABLE ntf.notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES core.users (id) ON DELETE CASCADE,
  business_id uuid REFERENCES core.businesses (id) ON DELETE CASCADE,
  type        text NOT NULL,
  title       text NOT NULL,
  body        text NOT NULL,
  data        jsonb NOT NULL DEFAULT '{}',
  dedupe_key  text,
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_inbox_idx ON ntf.notifications (user_id, created_at DESC, id DESC);
CREATE INDEX notifications_unread_idx ON ntf.notifications (user_id) WHERE read_at IS NULL;
-- Anti-doublon : rejouer un événement (relais at-least-once) ne crée jamais deux notifications.
CREATE UNIQUE INDEX notifications_dedupe_key ON ntf.notifications (user_id, dedupe_key)
  WHERE dedupe_key IS NOT NULL;

-- Préférences : absence de ligne = valeur par défaut du type (voir le registre applicatif).
CREATE TABLE ntf.notification_preferences (
  user_id uuid NOT NULL REFERENCES core.users (id) ON DELETE CASCADE,
  type    text NOT NULL,
  channel text NOT NULL CHECK (channel IN ('IN_APP', 'PUSH')),
  enabled boolean NOT NULL,
  PRIMARY KEY (user_id, type, channel)
);

-- Une ligne par (notification, canal) : l'état de livraison, jamais deviné depuis ailleurs.
CREATE TABLE ntf.notification_deliveries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL REFERENCES ntf.notifications (id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES core.users (id) ON DELETE CASCADE,
  channel         text NOT NULL CHECK (channel IN ('IN_APP', 'PUSH')),
  status          text NOT NULL CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'SKIPPED')),
  attempts        integer NOT NULL DEFAULT 0,
  last_error      text,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (notification_id, channel)
);

-- Jetons push (FCM). Un jeton n'appartient qu'à un utilisateur : se reconnecter avec un autre
-- compte sur le même téléphone REMPLACE le propriétaire (voir le service).
CREATE TABLE ntf.device_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES core.users (id) ON DELETE CASCADE,
  token        text NOT NULL UNIQUE,
  platform     text NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz
);
CREATE INDEX device_tokens_user_idx ON ntf.device_tokens (user_id) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- RLS : chaque ligne appartient à UN utilisateur, et lui seul la voit — y compris pour l'écriture
-- (le relais pose `app.user_id` du destinataire avant d'écrire, voir NotificationService).
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['notifications', 'notification_preferences', 'notification_deliveries', 'device_tokens']
  LOOP
    EXECUTE format('ALTER TABLE ntf.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE ntf.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format(
      $p$CREATE POLICY user_isolation ON ntf.%I
           USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
           WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)$p$, t);
  END LOOP;
END
$$;

-- Un jeton push identifie un TÉLÉPHONE. Si quelqu'un d'autre s'y connecte, l'ancien propriétaire ne
-- doit plus y recevoir ses notifications : détenir le jeton prouve qu'on tient l'appareil, donc le
-- service peut libérer les lignes portant CE jeton — et seulement celui-là (`app.device_token` posé
-- pour la durée de la transaction), jamais un DELETE sans clause qui viderait la table.
-- (PostgreSQL exige aussi une politique SELECT pour qu'un DELETE puisse lire la ligne qu'il vise.)
CREATE POLICY token_holder_release ON ntf.device_tokens FOR DELETE
  USING (token = NULLIF(current_setting('app.device_token', true), ''));
CREATE POLICY token_holder_see ON ntf.device_tokens FOR SELECT
  USING (token = NULLIF(current_setting('app.device_token', true), ''));
