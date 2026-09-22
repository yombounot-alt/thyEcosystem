-- THY Ecosystem — schéma du kernel (identité, tenancy, RBAC, plomberie transverse).
-- Référence : docs/blueprint/03-database.md, docs/blueprint/04-identity-access.md.
-- Ces tables sont migrées en SQL brut et possédées par le kernel : aucun module métier ne les
-- gère par son propre ORM (voir docs/plans/consolidation-strategy.md §2). Chaque module métier
-- (Business, Services, Academy…) aura son propre schéma PG (biz, svc, acd…) et son propre ORM.

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS ops;

-- Rendu self-suffisant pour tout environnement (staging Cloud SQL compris), même si
-- infra/docker/postgres/init/ les a déjà créées en local (idempotent).
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Rôle applicatif : jamais de contournement RLS (voir politiques plus bas). Idempotent.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'thy_app') THEN
    CREATE ROLE thy_app LOGIN PASSWORD 'changeme' NOBYPASSRLS;
  END IF;
END
$$;
GRANT USAGE ON SCHEMA core, ops TO thy_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA core, ops GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO thy_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA core, ops GRANT USAGE, SELECT ON SEQUENCES TO thy_app;

-- ---------------------------------------------------------------------------
-- Identité
-- ---------------------------------------------------------------------------

CREATE TABLE core.users (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone             text NOT NULL,
  phone_verified_at timestamptz,
  email             text,          -- normalisé en minuscules par l'application (voir CryptoService/AuthService)
  email_verified_at timestamptz,
  password_hash     text,                 -- optionnel (ADR-010) : OTP est le mécanisme principal
  full_name         text,
  locale            text NOT NULL DEFAULT 'fr',
  timezone          text NOT NULL DEFAULT 'UTC',
  status            text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'BANNED', 'DELETED')),
  token_version     integer NOT NULL DEFAULT 0,
  failed_login_count integer NOT NULL DEFAULT 0,
  locked_until      timestamptz,
  last_login_at     timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_phone_uq ON core.users (phone) WHERE status <> 'DELETED';
CREATE UNIQUE INDEX users_email_uq ON core.users (email) WHERE email IS NOT NULL AND status <> 'DELETED';

CREATE OR REPLACE FUNCTION core.set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON core.users
  FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- Défis OTP : indépendants de tout compte tant qu'ils ne sont pas vérifiés (voir 04-identity-access.md §2.2).
CREATE TABLE core.otp_challenges (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone       text NOT NULL,
  purpose     text NOT NULL CHECK (purpose IN ('LOGIN_OR_REGISTER')),
  code_hash   bytea NOT NULL,
  attempts    integer NOT NULL DEFAULT 0,
  expires_at  timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX otp_challenges_phone_purpose_idx ON core.otp_challenges (phone, purpose, created_at DESC);

CREATE TABLE core.refresh_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES core.users (id) ON DELETE CASCADE,
  family_id    uuid NOT NULL,
  token_hash   bytea NOT NULL,
  ip_hash      bytea,
  user_agent   text,
  expires_at   timestamptz NOT NULL,
  revoked_at   timestamptz,
  replaced_by  uuid REFERENCES core.refresh_tokens (id),
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX refresh_tokens_hash_uq ON core.refresh_tokens (token_hash);
CREATE INDEX refresh_tokens_family_idx ON core.refresh_tokens (family_id);
CREATE INDEX refresh_tokens_user_idx ON core.refresh_tokens (user_id);

CREATE TABLE core.login_events (
  id         bigserial PRIMARY KEY,
  user_id    uuid REFERENCES core.users (id) ON DELETE SET NULL,
  ip_hash    bytea,
  success    boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_events_user_idx ON core.login_events (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Entreprises (tenants) et adhésions
-- ---------------------------------------------------------------------------

CREATE TABLE core.businesses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL,
  business_type text,
  country      char(2) NOT NULL DEFAULT 'GN',
  currency     char(3) NOT NULL DEFAULT 'GNF',
  timezone     text NOT NULL DEFAULT 'Africa/Conakry',
  phone        text,
  address      text,
  owner_id     uuid NOT NULL REFERENCES core.users (id),
  status       text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'DELETED')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER businesses_set_updated_at BEFORE UPDATE ON core.businesses
  FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();
-- RLS activée plus bas (businesses_tenant_or_member), après core.business_members : la politique
-- référence cette table, qui doit donc déjà exister au moment du CREATE POLICY.

CREATE TABLE core.roles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL,
  scope       text NOT NULL CHECK (scope IN ('BUSINESS', 'PLATFORM')),
  business_id uuid REFERENCES core.businesses (id) ON DELETE CASCADE, -- NULL = rôle système partagé
  is_system   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX roles_system_code_uq ON core.roles (scope, code) WHERE business_id IS NULL;
CREATE UNIQUE INDEX roles_custom_code_uq ON core.roles (business_id, code) WHERE business_id IS NOT NULL;

CREATE TABLE core.permissions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,
  description text NOT NULL
);

CREATE TABLE core.role_permissions (
  role_id       uuid NOT NULL REFERENCES core.roles (id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES core.permissions (id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE core.business_members (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES core.users (id) ON DELETE CASCADE,
  role_id     uuid NOT NULL REFERENCES core.roles (id),
  status      text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (business_id, user_id),
  UNIQUE (business_id, id) -- cible de FK composites pour les modules métier (docs/blueprint/03-database.md §6)
);
CREATE INDEX business_members_business_idx ON core.business_members (business_id);
CREATE INDEX business_members_user_idx ON core.business_members (user_id);
CREATE TRIGGER business_members_set_updated_at BEFORE UPDATE ON core.business_members
  FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

ALTER TABLE core.business_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.business_members FORCE ROW LEVEL SECURITY;
CREATE POLICY business_members_tenant_or_self ON core.business_members
  USING (
    business_id = NULLIF(current_setting('app.business_id', true), '')::uuid
    OR user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
  );

-- RLS de core.businesses (déclarée ici : elle référence business_members, qui doit exister avant).
-- Visible en tant que tenant actif (app.business_id) OU en tant que membre (app.user_id) — ces
-- deux contextes sont posés par Db.withTenant() (voir kernel/db/db.service.ts).
ALTER TABLE core.businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.businesses FORCE ROW LEVEL SECURITY;
-- NB : `INSERT … RETURNING` réévalue USING (pas seulement WITH CHECK) pour décider si la ligne
-- tout juste insérée peut être renvoyée. Au moment de créer une entreprise, sa ligne
-- business_members n'existe pas encore (insérée par une requête suivante, même transaction) : sans
-- la clause `owner_id = app.user_id` ci-dessous, le RETURNING échouerait avec « new row violates
-- row-level security policy » alors que l'INSERT lui-même était pourtant autorisé.
CREATE POLICY businesses_tenant_or_member ON core.businesses
  USING (
    id = NULLIF(current_setting('app.business_id', true), '')::uuid
    OR owner_id = NULLIF(current_setting('app.user_id', true), '')::uuid
    OR EXISTS (
      SELECT 1 FROM core.business_members m
       WHERE m.business_id = businesses.id
         AND m.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
         AND m.status = 'ACTIVE'
    )
  )
  WITH CHECK (
    owner_id = NULLIF(current_setting('app.user_id', true), '')::uuid
    OR id = NULLIF(current_setting('app.business_id', true), '')::uuid
  );

CREATE TABLE core.business_invitations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  phone       text NOT NULL,
  role_id     uuid NOT NULL REFERENCES core.roles (id),
  token_hash  bytea NOT NULL,
  status      text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED')),
  created_by  uuid NOT NULL REFERENCES core.users (id),
  expires_at  timestamptz NOT NULL,
  accepted_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX business_invitations_hash_uq ON core.business_invitations (token_hash);
CREATE INDEX business_invitations_business_idx ON core.business_invitations (business_id, status);

-- Comptes staff (administration THY) : séparés des comptes clients dès le départ (ADR-010).
-- Non exploités par du code avant le lot admin (L0.11) — la table existe pour que le modèle de
-- rôles PLATFORM soit cohérent dès maintenant.
CREATE TABLE core.staff_users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text NOT NULL UNIQUE, -- normalisé en minuscules par l'application
  password_hash text NOT NULL,
  full_name     text NOT NULL,
  status        text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED')),
  token_version integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE core.staff_role_assignments (
  staff_id   uuid NOT NULL REFERENCES core.staff_users (id) ON DELETE CASCADE,
  role_id    uuid NOT NULL REFERENCES core.roles (id) ON DELETE CASCADE,
  PRIMARY KEY (staff_id, role_id)
);

-- ---------------------------------------------------------------------------
-- Plomberie transverse (schéma ops)
-- ---------------------------------------------------------------------------

CREATE TABLE ops.outbox_events (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type     text NOT NULL,
  aggregate_type text NOT NULL,
  aggregate_id   uuid,
  business_id    uuid,
  payload        jsonb NOT NULL,
  occurred_at    timestamptz NOT NULL DEFAULT now(),
  published_at   timestamptz,
  attempts       integer NOT NULL DEFAULT 0
);
CREATE INDEX outbox_pending_idx ON ops.outbox_events (occurred_at) WHERE published_at IS NULL;

CREATE TABLE ops.processed_events (
  consumer   text NOT NULL,
  event_id   uuid NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (consumer, event_id)
);

CREATE TABLE ops.idempotency_keys (
  user_id         uuid NOT NULL,
  key             text NOT NULL,
  endpoint        text NOT NULL,
  request_hash    bytea NOT NULL,
  response_status integer,
  response_body   jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key, endpoint)
);

CREATE TABLE ops.audit_logs (
  id          bigserial PRIMARY KEY,
  actor_id    uuid,
  action      text NOT NULL,
  target_type text,
  target_id   text,
  ip_hash     bytea,
  metadata    jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_target_idx ON ops.audit_logs (target_type, target_id);
CREATE INDEX audit_logs_actor_idx ON ops.audit_logs (actor_id, created_at DESC);

-- Append-only : aucune modification/suppression d'une ligne d'audit ou d'un événement publié.
CREATE OR REPLACE FUNCTION ops.forbid_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'Table % : append-only, modification interdite', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER audit_logs_forbid_mutation BEFORE UPDATE OR DELETE ON ops.audit_logs
  FOR EACH ROW EXECUTE FUNCTION ops.forbid_mutation();
