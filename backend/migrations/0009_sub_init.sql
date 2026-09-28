-- Abonnements et droits commerciaux (entitlements) — squelette L0.8.
-- Référence : docs/blueprint/04-identity-access.md §6. Les valeurs chiffrées des plans sont des
-- DONNÉES (plan_entitlements), pas du code : les changer = une migration de données, rien d'autre.
-- Valeurs initiales = « proposition initiale, à valider produit » du blueprint (§6.3).

CREATE SCHEMA IF NOT EXISTS sub;
GRANT USAGE ON SCHEMA sub TO thy_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA sub GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO thy_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA sub GRANT USAGE, SELECT ON SEQUENCES TO thy_app;

-- ---------------------------------------------------------------------------
-- Catalogue (référence, lisible par tous, sans RLS)
-- ---------------------------------------------------------------------------
CREATE TABLE sub.plans (
  code       text PRIMARY KEY,
  name       text NOT NULL,
  scope      text NOT NULL CHECK (scope IN ('BUSINESS', 'USER')),
  sort_order integer NOT NULL DEFAULT 0
);

CREATE TABLE sub.entitlements (
  code        text PRIMARY KEY,
  kind        text NOT NULL CHECK (kind IN ('BOOLEAN', 'LIMIT')),
  description text NOT NULL
);

-- `value` : pour une LIMITE, le maximum (NULL = illimité) ; pour un BOOLÉEN, 1 = accordé, 0 = non.
CREATE TABLE sub.plan_entitlements (
  plan_code        text NOT NULL REFERENCES sub.plans (code) ON DELETE CASCADE,
  entitlement_code text NOT NULL REFERENCES sub.entitlements (code) ON DELETE CASCADE,
  value            integer CHECK (value IS NULL OR value >= 0),
  PRIMARY KEY (plan_code, entitlement_code)
);

INSERT INTO sub.plans (code, name, scope, sort_order) VALUES
  ('FREE', 'Gratuit', 'BUSINESS', 0),
  ('PRO',  'Pro',     'BUSINESS', 1);

INSERT INTO sub.entitlements (code, kind, description) VALUES
  ('members.max',    'LIMIT',   'Nombre de membres de l''équipe (propriétaire compris, invitations en attente comprises)'),
  ('products.max',   'LIMIT',   'Nombre de produits actifs au catalogue'),
  ('locations.max',  'LIMIT',   'Nombre de points de vente'),
  ('reports.export', 'BOOLEAN', 'Export des rapports');

INSERT INTO sub.plan_entitlements (plan_code, entitlement_code, value) VALUES
  ('FREE', 'members.max',    3),
  ('FREE', 'products.max',   50),
  ('FREE', 'locations.max',  1),
  ('FREE', 'reports.export', 0),
  ('PRO',  'members.max',    5),
  ('PRO',  'products.max',   500),
  ('PRO',  'locations.max',  1),
  ('PRO',  'reports.export', 1);

-- ---------------------------------------------------------------------------
-- Abonnement de chaque entreprise (tenant, sous RLS)
-- ---------------------------------------------------------------------------
CREATE TABLE sub.subscriptions (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id        uuid NOT NULL UNIQUE REFERENCES core.businesses (id) ON DELETE CASCADE,
  plan_code          text NOT NULL REFERENCES sub.plans (code),
  status             text NOT NULL DEFAULT 'ACTIVE'
                       CHECK (status IN ('TRIALING', 'ACTIVE', 'PAST_DUE', 'GRACE', 'EXPIRED', 'CANCELED')),
  current_period_end timestamptz,          -- NULL : sans échéance (plan gratuit)
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER subscriptions_set_updated_at BEFORE UPDATE ON sub.subscriptions
  FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- Historique (changement de plan, dérogation…), en ajout seul.
CREATE TABLE sub.subscription_events (
  id          bigserial PRIMARY KEY,
  business_id uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  type        text NOT NULL,
  from_plan   text,
  to_plan     text,
  actor_id    uuid,
  metadata    jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX subscription_events_business_idx ON sub.subscription_events (business_id, created_at DESC);
CREATE TRIGGER subscription_events_forbid_mutation BEFORE UPDATE OR DELETE ON sub.subscription_events
  FOR EACH ROW EXECUTE FUNCTION ops.forbid_mutation();

-- Dérogation individuelle (geste commercial, support, pilote), éventuellement datée.
-- Remplace la valeur du plan pour CETTE entreprise ; NULL = illimité.
CREATE TABLE sub.entitlement_overrides (
  business_id      uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  entitlement_code text NOT NULL REFERENCES sub.entitlements (code) ON DELETE CASCADE,
  value            integer CHECK (value IS NULL OR value >= 0),
  reason           text NOT NULL,
  expires_at       timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, entitlement_code)
);

-- Les entreprises existantes reçoivent le plan gratuit (celles créées ensuite l'ont à la création ;
-- le service crée aussi l'abonnement gratuit s'il manque). Fait AVANT d'activer la RLS de sub.*.
INSERT INTO sub.subscriptions (business_id, plan_code) SELECT id, 'FREE' FROM core.businesses;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['subscriptions', 'subscription_events', 'entitlement_overrides']
  LOOP
    EXECUTE format('ALTER TABLE sub.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE sub.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON sub.%I
      USING (business_id = NULLIF(current_setting('app.business_id', true), '')::uuid)
      WITH CHECK (business_id = NULLIF(current_setting('app.business_id', true), '')::uuid)$p$, t);
  END LOOP;
END $$;


-- ---------------------------------------------------------------------------
-- Feature flags : pilotent le DÉPLOIEMENT (≠ droits commerciaux). Globaux, sans RLS.
-- ---------------------------------------------------------------------------
CREATE TABLE ops.feature_flags (
  key             text PRIMARY KEY CHECK (key ~ '^[a-z0-9_.]+$'),
  description     text NOT NULL,
  enabled         boolean NOT NULL DEFAULT false,   -- interrupteur général (kill-switch)
  rollout_percent integer NOT NULL DEFAULT 100 CHECK (rollout_percent BETWEEN 0 AND 100),
  countries       text[],                           -- NULL : tous les pays
  updated_at      timestamptz NOT NULL DEFAULT now()
);
