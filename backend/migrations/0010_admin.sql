-- Console d'administration (L0.11) : comptes staff avec double authentification TOTP obligatoire,
-- sessions courtes, rôles plateforme, et droits du rôle PostgreSQL `thy_admin_app` limités au strict
-- nécessaire. Référence : docs/blueprint/09-admin.md. Décision utilisateur du 2026-09-29 : comptes
-- THY + TOTP (le SSO OIDC pourra s'ajouter plus tard sur les mêmes comptes).

-- ---------------------------------------------------------------------------
-- Staff : TOTP, verrouillage, anti-rejeu
-- ---------------------------------------------------------------------------
ALTER TABLE core.staff_users
  -- Secret TOTP chiffré (AES-256-GCM, clé ADMIN_TOTP_KEY) ; NULL tant que non enrôlé.
  ADD COLUMN totp_secret_enc bytea,
  -- NULL : la double authentification n'est pas encore activée (enrôlement obligatoire à la 1re connexion).
  ADD COLUMN totp_enabled_at timestamptz,
  -- Dernier pas de temps TOTP accepté : un code déjà utilisé est refusé (anti-rejeu).
  ADD COLUMN totp_last_step bigint,
  ADD COLUMN failed_login_count integer NOT NULL DEFAULT 0,
  ADD COLUMN locked_until timestamptz,
  ADD COLUMN last_login_at timestamptz;
CREATE TRIGGER staff_users_set_updated_at BEFORE UPDATE ON core.staff_users
  FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- Session staff : cookie opaque (seule son empreinte est stockée). `mfa_verified_at` NULL = session
-- « à mi-chemin » (mot de passe vérifié, code TOTP attendu) : elle ne donne accès qu'à la double
-- authentification. `csrf_hash` : jeton anti-CSRF propre à la session (en-tête X-CSRF-Token).
CREATE TABLE core.staff_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id        uuid NOT NULL REFERENCES core.staff_users (id) ON DELETE CASCADE,
  token_hash      bytea NOT NULL UNIQUE,
  csrf_hash       bytea NOT NULL,
  mfa_verified_at timestamptz,
  ip_hash         bytea,
  user_agent      text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  revoked_at      timestamptz
);
CREATE INDEX staff_sessions_staff_idx ON core.staff_sessions (staff_id) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- Rôles et permissions plateforme (jamais déduits des rôles clients)
-- ---------------------------------------------------------------------------
INSERT INTO core.permissions (code, description) VALUES
  ('admin:users.read',        'Admin : rechercher et consulter les utilisateurs (numéros masqués)'),
  ('admin:users.reveal',      'Admin : afficher un numéro de téléphone en clair (action auditée)'),
  ('admin:users.restrict',    'Admin : suspendre / réactiver un compte, révoquer ses sessions'),
  ('admin:audit.read',        'Admin : consulter le journal d''audit'),
  ('admin:settings.manage',   'Admin : feature flags et dérogations d''offre'),
  ('admin:businesses.read',   'Admin : rechercher les entreprises et consulter leur offre')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.roles (code, scope, business_id, is_system) VALUES
  ('SUPER_ADMIN',   'PLATFORM', NULL, true),
  ('ADMIN',         'PLATFORM', NULL, true),
  ('SUPPORT_AGENT', 'PLATFORM', NULL, true)
ON CONFLICT (scope, code) WHERE business_id IS NULL DO NOTHING;

INSERT INTO core.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM (VALUES
  ('SUPER_ADMIN', 'admin:users.read'), ('SUPER_ADMIN', 'admin:users.reveal'),
  ('SUPER_ADMIN', 'admin:users.restrict'), ('SUPER_ADMIN', 'admin:audit.read'),
  ('SUPER_ADMIN', 'admin:settings.manage'), ('SUPER_ADMIN', 'admin:businesses.read'),

  ('ADMIN', 'admin:users.read'), ('ADMIN', 'admin:audit.read'),
  ('ADMIN', 'admin:settings.manage'), ('ADMIN', 'admin:businesses.read'),

  ('SUPPORT_AGENT', 'admin:users.read'), ('SUPPORT_AGENT', 'admin:users.reveal'),
  ('SUPPORT_AGENT', 'admin:users.restrict'), ('SUPPORT_AGENT', 'admin:businesses.read')
) AS matrix(role_code, permission_code)
JOIN core.roles r ON r.code = matrix.role_code AND r.scope = 'PLATFORM' AND r.business_id IS NULL
JOIN core.permissions p ON p.code = matrix.permission_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Audit : l'auteur d'une action est un utilisateur (app) OU un membre du staff (admin)
-- ---------------------------------------------------------------------------
ALTER TABLE ops.audit_logs
  ADD COLUMN actor_type text NOT NULL DEFAULT 'user' CHECK (actor_type IN ('user', 'staff', 'system'));
CREATE INDEX audit_logs_created_idx ON ops.audit_logs (created_at DESC, id DESC);
CREATE INDEX audit_logs_action_idx ON ops.audit_logs (action, created_at DESC);

-- ---------------------------------------------------------------------------
-- Rôle PostgreSQL de l'API admin : moindre privilège, droits EXPLICITES table par table.
-- (Le rôle existe partout avant les migrations : infra/docker/postgres/init en local et en CI,
-- bootstrap Terraform sur GCP. Un GRANT vers un rôle absent échoue : c'est voulu.)
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA core, ops, sub TO thy_admin_app;

GRANT SELECT, INSERT, UPDATE ON core.staff_users, core.staff_sessions TO thy_admin_app;
GRANT SELECT ON core.staff_role_assignments, core.roles, core.permissions, core.role_permissions
  TO thy_admin_app;

-- Utilisateurs : lecture ; seules colonnes modifiables = statut et version de jeton (suspension,
-- révocation) — pas de modification du profil par l'admin.
GRANT SELECT ON core.users, core.login_events TO thy_admin_app;
GRANT UPDATE (status, token_version) ON core.users TO thy_admin_app;
GRANT SELECT, UPDATE (revoked_at) ON core.refresh_tokens TO thy_admin_app;

-- Entreprises et adhésions : lecture seule, pour le support (nom, rôle d'un utilisateur). Ces tables
-- sont sous RLS forcée : une politique dédiée, en LECTURE et pour ce seul rôle.
GRANT SELECT ON core.businesses, core.business_members TO thy_admin_app;
CREATE POLICY admin_read ON core.businesses FOR SELECT TO thy_admin_app USING (true);
CREATE POLICY admin_read ON core.business_members FOR SELECT TO thy_admin_app USING (true);

-- Journal d'audit : lecture et ajout (jamais modification : trigger append-only).
GRANT SELECT, INSERT ON ops.audit_logs TO thy_admin_app;
GRANT USAGE, SELECT ON SEQUENCE ops.audit_logs_id_seq TO thy_admin_app;

-- Réglages : feature flags ; offre et dérogations des entreprises.
GRANT SELECT, INSERT, UPDATE ON ops.feature_flags TO thy_admin_app;
GRANT SELECT ON sub.plans, sub.entitlements, sub.plan_entitlements TO thy_admin_app;
GRANT SELECT ON sub.subscriptions TO thy_admin_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON sub.entitlement_overrides TO thy_admin_app;
GRANT SELECT, INSERT ON sub.subscription_events TO thy_admin_app;
GRANT USAGE, SELECT ON SEQUENCE sub.subscription_events_id_seq TO thy_admin_app;
CREATE POLICY admin_read ON sub.subscriptions FOR SELECT TO thy_admin_app USING (true);
CREATE POLICY admin_manage ON sub.entitlement_overrides FOR ALL TO thy_admin_app
  USING (true) WITH CHECK (true);
CREATE POLICY admin_append ON sub.subscription_events FOR ALL TO thy_admin_app
  USING (true) WITH CHECK (true);
