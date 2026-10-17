# Base de données

> **Fichier généré** par `backend/src/database/schema-doc-cli.ts` depuis le catalogue d'une base
> migrée. Ne pas le modifier à la main : changer les migrations (`backend/migrations/`), puis
> `pnpm --filter @thy/backend run db:doc`. La CI backend échoue s'il n'est plus à jour.

Conventions et choix : [ADR-003](adr/0003-acces-aux-donnees-et-migrations.md),
[ADR-004](adr/0004-isolation-multi-tenant.md), [ADR-016](adr/0016-identifiants-et-representation-de-l-argent.md),
[ADR-018](adr/0018-decouverte-de-code-existant-strategie-de-consolidation.md) ; cible complète :
[blueprint 03](blueprint/03-database.md).

## Rôles

| Rôle | Connexion | Contourne la RLS |
| --- | --- | --- |
| `thy_admin_app` | oui | non |
| `thy_app` | oui | non |
| `thy_migrator` | oui | **oui** |
| `thy_readonly` | oui | non |

## Migrations appliquées (12)

- `0001_core_init.sql`
- `0002_core_rbac_seed.sql`
- `0003_core_rbac_business_permissions.sql`
- `0004_biz_init.sql`
- `0005_ntf_init.sql`
- `0006_core_team_management.sql`
- `0007_biz_offline_sales.sql`
- `0008_biz_sale_counters.sql`
- `0009_sub_init.sql`
- `0010_admin.sql`
- `0011_table_comments.sql`
- `0012_append_only_history.sql`

## Sommaire

- **core** — Kernel : identité, entreprises (tenants), rôles et droits, staff.
  - [core.business_invitations](#corebusiness_invitations)
  - [core.business_members](#corebusiness_members)
  - [core.businesses](#corebusinesses)
  - [core.login_events](#corelogin_events)
  - [core.otp_challenges](#coreotp_challenges)
  - [core.permissions](#corepermissions)
  - [core.refresh_tokens](#corerefresh_tokens)
  - [core.role_permissions](#corerole_permissions)
  - [core.roles](#coreroles)
  - [core.staff_role_assignments](#corestaff_role_assignments)
  - [core.staff_sessions](#corestaff_sessions)
  - [core.staff_users](#corestaff_users)
  - [core.users](#coreusers)
- **ops** — Kernel : exploitation transverse (audit, outbox, idempotence, feature flags).
  - [ops.audit_logs](#opsaudit_logs)
  - [ops.feature_flags](#opsfeature_flags)
  - [ops.idempotency_keys](#opsidempotency_keys)
  - [ops.outbox_events](#opsoutbox_events)
  - [ops.processed_events](#opsprocessed_events)
- **ntf** — Kernel : notifications (in-app et push).
  - [ntf.device_tokens](#ntfdevice_tokens)
  - [ntf.notification_deliveries](#ntfnotification_deliveries)
  - [ntf.notification_preferences](#ntfnotification_preferences)
  - [ntf.notifications](#ntfnotifications)
- **sub** — Kernel : offres, abonnements et droits par entreprise.
  - [sub.entitlement_overrides](#subentitlement_overrides)
  - [sub.entitlements](#subentitlements)
  - [sub.plan_entitlements](#subplan_entitlements)
  - [sub.plans](#subplans)
  - [sub.subscription_events](#subsubscription_events)
  - [sub.subscriptions](#subsubscriptions)
- **biz** — Module Business (porté de thyBusiness) : catalogue, ventes, stock, clients, dépenses.
  - [biz.categories](#bizcategories)
  - [biz.credit_payments](#bizcredit_payments)
  - [biz.customer_credits](#bizcustomer_credits)
  - [biz.customers](#bizcustomers)
  - [biz.expenses](#bizexpenses)
  - [biz.inventory_movements](#bizinventory_movements)
  - [biz.manual_payments](#bizmanual_payments)
  - [biz.payment_methods](#bizpayment_methods)
  - [biz.payments](#bizpayments)
  - [biz.products](#bizproducts)
  - [biz.sale_counters](#bizsale_counters)
  - [biz.sale_items](#bizsale_items)
  - [biz.sales](#bizsales)
- **public** — standard public schema
  - [public.schema_migrations](#publicschema_migrations)

## Schéma `core`

Kernel : identité, entreprises (tenants), rôles et droits, staff.

### core.business_invitations

Invitation à rejoindre une entreprise, adressée à un numéro et acceptée dans l'app (pas de jeton dans un lien).

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `phone` | `text` | non |  |
| `role_id` | `uuid` | non |  |
| `token_hash` | `bytea` | oui |  |
| `status` | `text` | non | `'PENDING'::text` |
| `created_by` | `uuid` | non |  |
| `expires_at` | `timestamp with time zone` | non |  |
| `accepted_at` | `timestamp with time zone` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `responded_at` | `timestamp with time zone` | oui |  |

Contraintes :

- `business_invitations_status_check` : `CHECK ((status = ANY (ARRAY['PENDING'::text, 'ACCEPTED'::text, 'DECLINED'::text, 'REVOKED'::text, 'EXPIRED'::text])))`
- `business_invitations_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `business_invitations_created_by_fkey` : `FOREIGN KEY (created_by) REFERENCES core.users(id)`
- `business_invitations_role_id_fkey` : `FOREIGN KEY (role_id) REFERENCES core.roles(id)`
- `business_invitations_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX business_invitations_business_idx ON core.business_invitations USING btree (business_id, status)`
- `CREATE UNIQUE INDEX business_invitations_hash_uq ON core.business_invitations USING btree (token_hash)`
- `CREATE UNIQUE INDEX business_invitations_pending_uq ON core.business_invitations USING btree (business_id, phone) WHERE (status = 'PENDING'::text)`
- `CREATE INDEX business_invitations_phone_idx ON core.business_invitations USING btree (phone) WHERE (status = 'PENDING'::text)`

Politiques RLS :

- `business_invitations_tenant_or_invitee` — ALL, rôles PUBLIC; USING `((business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid) OR (phone = core.current_user_phone()))`; WITH CHECK `((business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid) OR (phone = core.current_user_phone()))`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### core.business_members

Appartenance d'un utilisateur à une entreprise, avec son rôle.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `user_id` | `uuid` | non |  |
| `role_id` | `uuid` | non |  |
| `status` | `text` | non | `'ACTIVE'::text` |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `updated_at` | `timestamp with time zone` | non | `now()` |
| `permission_overrides` — Écarts par rapport aux permissions par défaut du rôle : {"sales:refund": true, "credits:manage": false}. members:manage et subscription:manage ne sont jamais surchargeables. | `jsonb` | oui |  |

Contraintes :

- `business_members_status_check` : `CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'SUSPENDED'::text, 'REMOVED'::text])))`
- `business_members_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `business_members_role_id_fkey` : `FOREIGN KEY (role_id) REFERENCES core.roles(id)`
- `business_members_user_id_fkey` : `FOREIGN KEY (user_id) REFERENCES core.users(id) ON DELETE CASCADE`
- `business_members_pkey` : `PRIMARY KEY (id)`
- `business_members_business_id_id_key` : `UNIQUE (business_id, id)`
- `business_members_business_id_user_id_key` : `UNIQUE (business_id, user_id)`

Index :

- `CREATE INDEX business_members_business_idx ON core.business_members USING btree (business_id)`
- `CREATE INDEX business_members_user_idx ON core.business_members USING btree (user_id)`

Politiques RLS :

- `admin_read` — SELECT, rôles thy_admin_app; USING `true`
- `business_members_tenant_or_self` — ALL, rôles PUBLIC; USING `((business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid) OR (user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid))`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### core.businesses

Entreprise : le tenant. Toute donnée métier porte son business_id.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `name` | `text` | non |  |
| `business_type` | `text` | oui |  |
| `country` | `character(2)` | non | `'GN'::bpchar` |
| `currency` | `character(3)` | non | `'GNF'::bpchar` |
| `timezone` | `text` | non | `'Africa/Conakry'::text` |
| `phone` | `text` | oui |  |
| `address` | `text` | oui |  |
| `owner_id` | `uuid` | non |  |
| `status` | `text` | non | `'ACTIVE'::text` |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `updated_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `businesses_status_check` : `CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'SUSPENDED'::text, 'DELETED'::text])))`
- `businesses_owner_id_fkey` : `FOREIGN KEY (owner_id) REFERENCES core.users(id)`
- `businesses_pkey` : `PRIMARY KEY (id)`

Politiques RLS :

- `admin_read` — SELECT, rôles thy_admin_app; USING `true`
- `businesses_tenant_or_member` — ALL, rôles PUBLIC; USING `((id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid) OR (owner_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid) OR (EXISTS ( SELECT 1
   FROM core.business_members m
  WHERE ((m.business_id = businesses.id) AND (m.user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid) AND (m.status = 'ACTIVE'::text)))) OR (EXISTS ( SELECT 1
   FROM core.business_invitations i
  WHERE ((i.business_id = businesses.id) AND (i.status = 'PENDING'::text) AND (i.phone = core.current_user_phone())))))`; WITH CHECK `((owner_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid) OR (id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid))`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### core.login_events

Historique des tentatives de connexion des clients (réussies ou non).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `bigint` | non | `nextval('core.login_events_id_seq'::regclass)` |
| `user_id` | `uuid` | oui |  |
| `ip_hash` | `bytea` | oui |  |
| `success` | `boolean` | non |  |
| `created_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `login_events_user_id_fkey` : `FOREIGN KEY (user_id) REFERENCES core.users(id) ON DELETE SET NULL`
- `login_events_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX login_events_user_idx ON core.login_events USING btree (user_id, created_at DESC)`

Droits :

- `thy_app` : SELECT, INSERT
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### core.otp_challenges

Code de connexion envoyé par SMS : stocké haché, à durée de vie courte, tentatives limitées.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `phone` | `text` | non |  |
| `purpose` | `text` | non |  |
| `code_hash` | `bytea` | non |  |
| `attempts` | `integer` | non | `0` |
| `expires_at` | `timestamp with time zone` | non |  |
| `consumed_at` | `timestamp with time zone` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `otp_challenges_purpose_check` : `CHECK ((purpose = 'LOGIN_OR_REGISTER'::text))`
- `otp_challenges_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX otp_challenges_phone_purpose_idx ON core.otp_challenges USING btree (phone, purpose, created_at DESC)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### core.permissions

Catalogue des droits (codes stables, par exemple sales:create, admin:users.read).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `code` | `text` | non |  |
| `description` | `text` | non |  |

Contraintes :

- `permissions_pkey` : `PRIMARY KEY (id)`
- `permissions_code_key` : `UNIQUE (code)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### core.refresh_tokens

Jeton de rafraîchissement opaque (haché) ; une famille par appareil, révoquée en bloc si un jeton est réutilisé.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `user_id` | `uuid` | non |  |
| `family_id` | `uuid` | non |  |
| `token_hash` | `bytea` | non |  |
| `ip_hash` | `bytea` | oui |  |
| `user_agent` | `text` | oui |  |
| `expires_at` | `timestamp with time zone` | non |  |
| `revoked_at` | `timestamp with time zone` | oui |  |
| `replaced_by` | `uuid` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `refresh_tokens_replaced_by_fkey` : `FOREIGN KEY (replaced_by) REFERENCES core.refresh_tokens(id)`
- `refresh_tokens_user_id_fkey` : `FOREIGN KEY (user_id) REFERENCES core.users(id) ON DELETE CASCADE`
- `refresh_tokens_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX refresh_tokens_family_idx ON core.refresh_tokens USING btree (family_id)`
- `CREATE UNIQUE INDEX refresh_tokens_hash_uq ON core.refresh_tokens USING btree (token_hash)`
- `CREATE INDEX refresh_tokens_user_idx ON core.refresh_tokens USING btree (user_id)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT, UPDATE (revoked_at)
- `thy_readonly` : aucun

### core.role_permissions

Droits accordés à chaque rôle.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `role_id` | `uuid` | non |  |
| `permission_id` | `uuid` | non |  |

Contraintes :

- `role_permissions_permission_id_fkey` : `FOREIGN KEY (permission_id) REFERENCES core.permissions(id) ON DELETE CASCADE`
- `role_permissions_role_id_fkey` : `FOREIGN KEY (role_id) REFERENCES core.roles(id) ON DELETE CASCADE`
- `role_permissions_pkey` : `PRIMARY KEY (role_id, permission_id)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### core.roles

Rôle : de portée BUSINESS (propriétaire, gérant, caissier…) ou PLATFORM (staff THY).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `code` | `text` | non |  |
| `scope` | `text` | non |  |
| `business_id` | `uuid` | oui |  |
| `is_system` | `boolean` | non | `true` |
| `created_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `roles_scope_check` : `CHECK ((scope = ANY (ARRAY['BUSINESS'::text, 'PLATFORM'::text])))`
- `roles_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `roles_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE UNIQUE INDEX roles_custom_code_uq ON core.roles USING btree (business_id, code) WHERE (business_id IS NOT NULL)`
- `CREATE UNIQUE INDEX roles_system_code_uq ON core.roles USING btree (scope, code) WHERE (business_id IS NULL)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### core.staff_role_assignments

Rôles plateforme attribués à un membre du staff.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `staff_id` | `uuid` | non |  |
| `role_id` | `uuid` | non |  |

Contraintes :

- `staff_role_assignments_role_id_fkey` : `FOREIGN KEY (role_id) REFERENCES core.roles(id) ON DELETE CASCADE`
- `staff_role_assignments_staff_id_fkey` : `FOREIGN KEY (staff_id) REFERENCES core.staff_users(id) ON DELETE CASCADE`
- `staff_role_assignments_pkey` : `PRIMARY KEY (staff_id, role_id)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### core.staff_sessions

Session de la console d'administration (jeton et jeton anti-CSRF stockés hachés).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `staff_id` | `uuid` | non |  |
| `token_hash` | `bytea` | non |  |
| `csrf_hash` | `bytea` | non |  |
| `mfa_verified_at` | `timestamp with time zone` | oui |  |
| `ip_hash` | `bytea` | oui |  |
| `user_agent` | `text` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `last_seen_at` | `timestamp with time zone` | non | `now()` |
| `expires_at` | `timestamp with time zone` | non |  |
| `revoked_at` | `timestamp with time zone` | oui |  |

Contraintes :

- `staff_sessions_staff_id_fkey` : `FOREIGN KEY (staff_id) REFERENCES core.staff_users(id) ON DELETE CASCADE`
- `staff_sessions_pkey` : `PRIMARY KEY (id)`
- `staff_sessions_token_hash_key` : `UNIQUE (token_hash)`

Index :

- `CREATE INDEX staff_sessions_staff_idx ON core.staff_sessions USING btree (staff_id) WHERE (revoked_at IS NULL)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT, INSERT, UPDATE
- `thy_readonly` : aucun

### core.staff_users

Compte du staff THY pour la console d'administration (mot de passe argon2id, TOTP chiffré).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `email` | `text` | non |  |
| `password_hash` | `text` | non |  |
| `full_name` | `text` | non |  |
| `status` | `text` | non | `'ACTIVE'::text` |
| `token_version` | `integer` | non | `0` |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `updated_at` | `timestamp with time zone` | non | `now()` |
| `totp_secret_enc` | `bytea` | oui |  |
| `totp_enabled_at` | `timestamp with time zone` | oui |  |
| `totp_last_step` | `bigint` | oui |  |
| `failed_login_count` | `integer` | non | `0` |
| `locked_until` | `timestamp with time zone` | oui |  |
| `last_login_at` | `timestamp with time zone` | oui |  |

Contraintes :

- `staff_users_status_check` : `CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'SUSPENDED'::text])))`
- `staff_users_pkey` : `PRIMARY KEY (id)`
- `staff_users_email_key` : `UNIQUE (email)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT, INSERT, UPDATE
- `thy_readonly` : aucun

### core.users

Compte client, identifié par un numéro de téléphone vérifié (E.164).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `phone` | `text` | non |  |
| `phone_verified_at` | `timestamp with time zone` | oui |  |
| `email` | `text` | oui |  |
| `email_verified_at` | `timestamp with time zone` | oui |  |
| `password_hash` | `text` | oui |  |
| `full_name` | `text` | oui |  |
| `locale` | `text` | non | `'fr'::text` |
| `timezone` | `text` | non | `'UTC'::text` |
| `status` | `text` | non | `'ACTIVE'::text` |
| `token_version` | `integer` | non | `0` |
| `failed_login_count` | `integer` | non | `0` |
| `locked_until` | `timestamp with time zone` | oui |  |
| `last_login_at` | `timestamp with time zone` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `updated_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `users_status_check` : `CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'SUSPENDED'::text, 'BANNED'::text, 'DELETED'::text])))`
- `users_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE UNIQUE INDEX users_email_uq ON core.users USING btree (email) WHERE ((email IS NOT NULL) AND (status <> 'DELETED'::text))`
- `CREATE UNIQUE INDEX users_phone_uq ON core.users USING btree (phone) WHERE (status <> 'DELETED'::text)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT, UPDATE (status, token_version)
- `thy_readonly` : aucun

## Schéma `ops`

Kernel : exploitation transverse (audit, outbox, idempotence, feature flags).

### ops.audit_logs

Journal d'audit en ajout seul : qui (utilisateur, staff ou système) a fait quoi, sur quoi, et pourquoi.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `bigint` | non | `nextval('ops.audit_logs_id_seq'::regclass)` |
| `actor_id` | `uuid` | oui |  |
| `action` | `text` | non |  |
| `target_type` | `text` | oui |  |
| `target_id` | `text` | oui |  |
| `ip_hash` | `bytea` | oui |  |
| `metadata` | `jsonb` | non | `'{}'::jsonb` |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `actor_type` | `text` | non | `'user'::text` |

Contraintes :

- `audit_logs_actor_type_check` : `CHECK ((actor_type = ANY (ARRAY['user'::text, 'staff'::text, 'system'::text])))`
- `audit_logs_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX audit_logs_action_idx ON ops.audit_logs USING btree (action, created_at DESC)`
- `CREATE INDEX audit_logs_actor_idx ON ops.audit_logs USING btree (actor_id, created_at DESC)`
- `CREATE INDEX audit_logs_created_idx ON ops.audit_logs USING btree (created_at DESC, id DESC)`
- `CREATE INDEX audit_logs_target_idx ON ops.audit_logs USING btree (target_type, target_id)`

Droits :

- `thy_app` : SELECT, INSERT
- `thy_admin_app` : SELECT, INSERT
- `thy_readonly` : aucun

### ops.feature_flags

Fonctionnalités activables par part d'utilisateurs et par pays, gérées depuis l'admin.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `key` | `text` | non |  |
| `description` | `text` | non |  |
| `enabled` | `boolean` | non | `false` |
| `rollout_percent` | `integer` | non | `100` |
| `countries` | `text[]` | oui |  |
| `updated_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `feature_flags_key_check` : `CHECK ((key ~ '^[a-z0-9_.]+$'::text))`
- `feature_flags_rollout_percent_check` : `CHECK (((rollout_percent >= 0) AND (rollout_percent <= 100)))`
- `feature_flags_pkey` : `PRIMARY KEY (key)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT, INSERT, UPDATE
- `thy_readonly` : aucun

### ops.idempotency_keys

Réponses mémorisées par clé d'idempotence, pour rejouer une requête sans effet double.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `user_id` | `uuid` | non |  |
| `key` | `text` | non |  |
| `endpoint` | `text` | non |  |
| `request_hash` | `bytea` | non |  |
| `response_status` | `integer` | oui |  |
| `response_body` | `jsonb` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `idempotency_keys_pkey` : `PRIMARY KEY (user_id, key, endpoint)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### ops.outbox_events

Événements à publier, écrits dans la même transaction que le changement qui les produit.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `event_type` | `text` | non |  |
| `aggregate_type` | `text` | non |  |
| `aggregate_id` | `uuid` | oui |  |
| `business_id` | `uuid` | oui |  |
| `payload` | `jsonb` | non |  |
| `occurred_at` | `timestamp with time zone` | non | `now()` |
| `published_at` | `timestamp with time zone` | oui |  |
| `attempts` | `integer` | non | `0` |
| `next_attempt_at` | `timestamp with time zone` | non | `now()` |
| `failed_at` | `timestamp with time zone` | oui |  |
| `last_error` | `text` | oui |  |

Contraintes :

- `outbox_events_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX outbox_dead_idx ON ops.outbox_events USING btree (failed_at) WHERE (failed_at IS NOT NULL)`
- `CREATE INDEX outbox_ready_idx ON ops.outbox_events USING btree (next_attempt_at) WHERE ((published_at IS NULL) AND (failed_at IS NULL))`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### ops.processed_events

Événements déjà traités par chaque consommateur, pour un traitement idempotent.

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `consumer` | `text` | non |  |
| `event_id` | `uuid` | non |  |
| `processed_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `processed_events_pkey` : `PRIMARY KEY (consumer, event_id)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

## Schéma `ntf`

Kernel : notifications (in-app et push).

### ntf.device_tokens

Jeton push d'un appareil, rattaché à l'utilisateur connecté sur cet appareil.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `user_id` | `uuid` | non |  |
| `token` | `text` | non |  |
| `platform` | `text` | non |  |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `last_seen_at` | `timestamp with time zone` | non | `now()` |
| `revoked_at` | `timestamp with time zone` | oui |  |

Contraintes :

- `device_tokens_platform_check` : `CHECK ((platform = ANY (ARRAY['android'::text, 'ios'::text, 'web'::text])))`
- `device_tokens_user_id_fkey` : `FOREIGN KEY (user_id) REFERENCES core.users(id) ON DELETE CASCADE`
- `device_tokens_pkey` : `PRIMARY KEY (id)`
- `device_tokens_token_key` : `UNIQUE (token)`

Index :

- `CREATE INDEX device_tokens_user_idx ON ntf.device_tokens USING btree (user_id) WHERE (revoked_at IS NULL)`

Politiques RLS :

- `token_holder_release` — DELETE, rôles PUBLIC; USING `(token = NULLIF(current_setting('app.device_token'::text, true), ''::text))`
- `token_holder_see` — SELECT, rôles PUBLIC; USING `(token = NULLIF(current_setting('app.device_token'::text, true), ''::text))`
- `user_isolation` — ALL, rôles PUBLIC; USING `(user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)`; WITH CHECK `(user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### ntf.notification_deliveries

Tentative d'envoi d'une notification sur un canal (in-app, push).

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `notification_id` | `uuid` | non |  |
| `user_id` | `uuid` | non |  |
| `channel` | `text` | non |  |
| `status` | `text` | non |  |
| `attempts` | `integer` | non | `0` |
| `last_error` | `text` | oui |  |
| `updated_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `notification_deliveries_channel_check` : `CHECK ((channel = ANY (ARRAY['IN_APP'::text, 'PUSH'::text])))`
- `notification_deliveries_status_check` : `CHECK ((status = ANY (ARRAY['PENDING'::text, 'SENT'::text, 'FAILED'::text, 'SKIPPED'::text])))`
- `notification_deliveries_notification_id_fkey` : `FOREIGN KEY (notification_id) REFERENCES ntf.notifications(id) ON DELETE CASCADE`
- `notification_deliveries_user_id_fkey` : `FOREIGN KEY (user_id) REFERENCES core.users(id) ON DELETE CASCADE`
- `notification_deliveries_pkey` : `PRIMARY KEY (id)`
- `notification_deliveries_notification_id_channel_key` : `UNIQUE (notification_id, channel)`

Politiques RLS :

- `user_isolation` — ALL, rôles PUBLIC; USING `(user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)`; WITH CHECK `(user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### ntf.notification_preferences

Choix de l'utilisateur par type de notification et par canal.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `user_id` | `uuid` | non |  |
| `type` | `text` | non |  |
| `channel` | `text` | non |  |
| `enabled` | `boolean` | non |  |

Contraintes :

- `notification_preferences_channel_check` : `CHECK ((channel = ANY (ARRAY['IN_APP'::text, 'PUSH'::text])))`
- `notification_preferences_user_id_fkey` : `FOREIGN KEY (user_id) REFERENCES core.users(id) ON DELETE CASCADE`
- `notification_preferences_pkey` : `PRIMARY KEY (user_id, type, channel)`

Politiques RLS :

- `user_isolation` — ALL, rôles PUBLIC; USING `(user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)`; WITH CHECK `(user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### ntf.notifications

Notification destinée à un utilisateur (contenu et état de lecture).

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `user_id` | `uuid` | non |  |
| `business_id` | `uuid` | oui |  |
| `type` | `text` | non |  |
| `title` | `text` | non |  |
| `body` | `text` | non |  |
| `data` | `jsonb` | non | `'{}'::jsonb` |
| `dedupe_key` | `text` | oui |  |
| `read_at` | `timestamp with time zone` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `notifications_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `notifications_user_id_fkey` : `FOREIGN KEY (user_id) REFERENCES core.users(id) ON DELETE CASCADE`
- `notifications_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE UNIQUE INDEX notifications_dedupe_key ON ntf.notifications USING btree (user_id, dedupe_key) WHERE (dedupe_key IS NOT NULL)`
- `CREATE INDEX notifications_inbox_idx ON ntf.notifications USING btree (user_id, created_at DESC, id DESC)`
- `CREATE INDEX notifications_unread_idx ON ntf.notifications USING btree (user_id) WHERE (read_at IS NULL)`

Politiques RLS :

- `user_isolation` — ALL, rôles PUBLIC; USING `(user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)`; WITH CHECK `(user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

## Schéma `sub`

Kernel : offres, abonnements et droits par entreprise.

### sub.entitlement_overrides

Dérogation à la valeur de l'offre pour une entreprise, accordée depuis l'admin, avec motif et échéance facultative.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `business_id` | `uuid` | non |  |
| `entitlement_code` | `text` | non |  |
| `value` | `integer` | oui |  |
| `reason` | `text` | non |  |
| `expires_at` | `timestamp with time zone` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `entitlement_overrides_value_check` : `CHECK (((value IS NULL) OR (value >= 0)))`
- `entitlement_overrides_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `entitlement_overrides_entitlement_code_fkey` : `FOREIGN KEY (entitlement_code) REFERENCES sub.entitlements(code) ON DELETE CASCADE`
- `entitlement_overrides_pkey` : `PRIMARY KEY (business_id, entitlement_code)`

Politiques RLS :

- `admin_manage` — ALL, rôles thy_admin_app; USING `true`; WITH CHECK `true`
- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_readonly` : aucun

### sub.entitlements

Catalogue des droits d'offre : limites (LIMIT) ou fonctionnalités (BOOLEAN).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `code` | `text` | non |  |
| `kind` | `text` | non |  |
| `description` | `text` | non |  |

Contraintes :

- `entitlements_kind_check` : `CHECK ((kind = ANY (ARRAY['BOOLEAN'::text, 'LIMIT'::text])))`
- `entitlements_pkey` : `PRIMARY KEY (code)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### sub.plan_entitlements

Valeur de chaque droit pour chaque offre (NULL = illimité).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `plan_code` | `text` | non |  |
| `entitlement_code` | `text` | non |  |
| `value` | `integer` | oui |  |

Contraintes :

- `plan_entitlements_value_check` : `CHECK (((value IS NULL) OR (value >= 0)))`
- `plan_entitlements_entitlement_code_fkey` : `FOREIGN KEY (entitlement_code) REFERENCES sub.entitlements(code) ON DELETE CASCADE`
- `plan_entitlements_plan_code_fkey` : `FOREIGN KEY (plan_code) REFERENCES sub.plans(code) ON DELETE CASCADE`
- `plan_entitlements_pkey` : `PRIMARY KEY (plan_code, entitlement_code)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### sub.plans

Offre commerciale (FREE, PRO…).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `code` | `text` | non |  |
| `name` | `text` | non |  |
| `scope` | `text` | non |  |
| `sort_order` | `integer` | non | `0` |

Contraintes :

- `plans_scope_check` : `CHECK ((scope = ANY (ARRAY['BUSINESS'::text, 'USER'::text])))`
- `plans_pkey` : `PRIMARY KEY (code)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

### sub.subscription_events

Historique en ajout seul de l'abonnement : début, changement d'offre, dérogations.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `bigint` | non | `nextval('sub.subscription_events_id_seq'::regclass)` |
| `business_id` | `uuid` | non |  |
| `type` | `text` | non |  |
| `from_plan` | `text` | oui |  |
| `to_plan` | `text` | oui |  |
| `actor_id` | `uuid` | oui |  |
| `metadata` | `jsonb` | non | `'{}'::jsonb` |
| `created_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `subscription_events_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `subscription_events_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX subscription_events_business_idx ON sub.subscription_events USING btree (business_id, created_at DESC)`

Politiques RLS :

- `admin_append` — ALL, rôles thy_admin_app; USING `true`; WITH CHECK `true`
- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT
- `thy_admin_app` : SELECT, INSERT
- `thy_readonly` : aucun

### sub.subscriptions

Abonnement en cours d'une entreprise (une ligne par entreprise).

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `plan_code` | `text` | non |  |
| `status` | `text` | non | `'ACTIVE'::text` |
| `current_period_end` | `timestamp with time zone` | oui |  |
| `created_at` | `timestamp with time zone` | non | `now()` |
| `updated_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `subscriptions_status_check` : `CHECK ((status = ANY (ARRAY['TRIALING'::text, 'ACTIVE'::text, 'PAST_DUE'::text, 'GRACE'::text, 'EXPIRED'::text, 'CANCELED'::text])))`
- `subscriptions_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `subscriptions_plan_code_fkey` : `FOREIGN KEY (plan_code) REFERENCES sub.plans(code)`
- `subscriptions_pkey` : `PRIMARY KEY (id)`
- `subscriptions_business_id_key` : `UNIQUE (business_id)`

Politiques RLS :

- `admin_read` — SELECT, rôles thy_admin_app; USING `true`
- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : SELECT
- `thy_readonly` : aucun

## Schéma `biz`

Module Business (porté de thyBusiness) : catalogue, ventes, stock, clients, dépenses.

### biz.categories

Catégorie de produits d'une entreprise.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `name` | `text` | non |  |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `updated_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `categories_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `categories_pkey` : `PRIMARY KEY (id)`
- `categories_business_id_id_key` : `UNIQUE (business_id, id)`
- `categories_business_id_name_key` : `UNIQUE (business_id, name)`

Index :

- `CREATE INDEX categories_business_idx ON biz.categories USING btree (business_id)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.credit_payments

Remboursement d'un crédit client.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `customer_id` | `uuid` | non |  |
| `customer_credit_id` | `uuid` | non |  |
| `amount` | `numeric(14,2)` | non |  |
| `method` | `text` | non |  |
| `received_by` | `uuid` | non |  |
| `note` | `text` | oui |  |
| `paid_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `credit_payments_business_id_customer_credit_id_fkey` : `FOREIGN KEY (business_id, customer_credit_id) REFERENCES biz.customer_credits(business_id, id)`
- `credit_payments_business_id_customer_id_fkey` : `FOREIGN KEY (business_id, customer_id) REFERENCES biz.customers(business_id, id)`
- `credit_payments_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `credit_payments_received_by_fkey` : `FOREIGN KEY (received_by) REFERENCES core.users(id)`
- `credit_payments_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX credit_payments_customer_idx ON biz.credit_payments USING btree (business_id, customer_id)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.customer_credits

Crédit accordé à un client (vente à crédit) : montant initial, reste dû, échéance.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `customer_id` | `uuid` | non |  |
| `sale_id` | `uuid` | oui |  |
| `original_amount` | `numeric(14,2)` | non |  |
| `remaining_amount` | `numeric(14,2)` | non |  |
| `status` | `text` | non | `'open'::text` |
| `due_date` | `date` | oui |  |
| `note` | `text` | oui |  |
| `created_by` | `uuid` | non |  |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `updated_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `customer_credits_business_id_customer_id_fkey` : `FOREIGN KEY (business_id, customer_id) REFERENCES biz.customers(business_id, id)`
- `customer_credits_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `customer_credits_business_id_sale_id_fkey` : `FOREIGN KEY (business_id, sale_id) REFERENCES biz.sales(business_id, id) ON DELETE SET NULL (sale_id)`
- `customer_credits_created_by_fkey` : `FOREIGN KEY (created_by) REFERENCES core.users(id)`
- `customer_credits_pkey` : `PRIMARY KEY (id)`
- `customer_credits_business_id_id_key` : `UNIQUE (business_id, id)`

Index :

- `CREATE INDEX customer_credits_customer_idx ON biz.customer_credits USING btree (business_id, customer_id)`
- `CREATE INDEX customer_credits_status_idx ON biz.customer_credits USING btree (business_id, status)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.customers

Client d'une entreprise (carnet de clients du commerçant).

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `full_name` | `text` | non |  |
| `phone` | `text` | oui |  |
| `address` | `text` | oui |  |
| `notes` | `text` | oui |  |
| `current_balance` | `numeric(14,2)` | non | `0` |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `updated_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `customers_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `customers_pkey` : `PRIMARY KEY (id)`
- `customers_business_id_id_key` : `UNIQUE (business_id, id)`

Index :

- `CREATE INDEX customers_business_name_idx ON biz.customers USING btree (business_id, full_name)`
- `CREATE INDEX customers_business_phone_idx ON biz.customers USING btree (business_id, phone)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.expenses

Dépense de l'entreprise.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `category` | `text` | non |  |
| `amount` | `numeric(14,2)` | non |  |
| `description` | `text` | oui |  |
| `expense_date` | `date` | non | `CURRENT_DATE` |
| `recorded_by` | `uuid` | non |  |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `updated_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `expenses_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `expenses_recorded_by_fkey` : `FOREIGN KEY (recorded_by) REFERENCES core.users(id)`
- `expenses_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX expenses_business_date_idx ON biz.expenses USING btree (business_id, expense_date)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.inventory_movements

Journal de stock en ajout seul : un mouvement ne se corrige que par un mouvement inverse.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `product_id` | `uuid` | non |  |
| `type` | `text` | non |  |
| `quantity` | `numeric(14,2)` | non |  |
| `unit_cost` | `numeric(14,2)` | oui |  |
| `reference_type` | `text` | oui |  |
| `reference_id` | `text` | oui |  |
| `note` | `text` | oui |  |
| `created_by` | `uuid` | non |  |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `inventory_movements_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `inventory_movements_business_id_product_id_fkey` : `FOREIGN KEY (business_id, product_id) REFERENCES biz.products(business_id, id)`
- `inventory_movements_created_by_fkey` : `FOREIGN KEY (created_by) REFERENCES core.users(id)`
- `inventory_movements_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX inventory_movements_product_idx ON biz.inventory_movements USING btree (business_id, product_id, created_at)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.manual_payments

Paiement direct envoyé par un client sur un moyen du commerçant, déclaré avec référence ou preuve, puis confirmé ou refusé. Aucun prestataire de paiement.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `created_by` | `uuid` | non |  |
| `payment_method_id` | `uuid` | oui |  |
| `method_provider` | `text` | non |  |
| `method_name` | `text` | non |  |
| `sent_to_holder` | `text` | oui |  |
| `sent_to_phone` | `text` | oui |  |
| `sent_to_code` | `text` | oui |  |
| `client_request_id` | `text` | non |  |
| `amount` | `numeric(14,2)` | non |  |
| `currency` | `text` | non | `'GNF'::text` |
| `status` | `text` | non | `'pending'::text` |
| `checkout` | `jsonb` | non |  |
| `sale_id` | `uuid` | oui |  |
| `payer_name` | `text` | oui |  |
| `payer_phone` | `text` | oui |  |
| `transaction_reference` | `text` | oui |  |
| `reference_key` | `text` | oui |  |
| `amount_sent` | `numeric(14,2)` | oui |  |
| `paid_at` | `timestamp(3) without time zone` | oui |  |
| `proof_key` | `text` | oui |  |
| `submitted_at` | `timestamp(3) without time zone` | oui |  |
| `verified_at` | `timestamp(3) without time zone` | oui |  |
| `verified_by` | `uuid` | oui |  |
| `rejected_at` | `timestamp(3) without time zone` | oui |  |
| `rejected_by` | `uuid` | oui |  |
| `rejection_reason` | `text` | oui |  |
| `cancelled_at` | `timestamp(3) without time zone` | oui |  |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `updated_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `manual_payments_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `manual_payments_business_id_payment_method_id_fkey` : `FOREIGN KEY (business_id, payment_method_id) REFERENCES biz.payment_methods(business_id, id) ON DELETE SET NULL (payment_method_id)`
- `manual_payments_business_id_sale_id_fkey` : `FOREIGN KEY (business_id, sale_id) REFERENCES biz.sales(business_id, id) ON DELETE SET NULL (sale_id)`
- `manual_payments_created_by_fkey` : `FOREIGN KEY (created_by) REFERENCES core.users(id)`
- `manual_payments_rejected_by_fkey` : `FOREIGN KEY (rejected_by) REFERENCES core.users(id) ON DELETE SET NULL`
- `manual_payments_verified_by_fkey` : `FOREIGN KEY (verified_by) REFERENCES core.users(id) ON DELETE SET NULL`
- `manual_payments_pkey` : `PRIMARY KEY (id)`
- `manual_payments_business_id_client_request_id_key` : `UNIQUE (business_id, client_request_id)`
- `manual_payments_sale_id_key` : `UNIQUE (sale_id)`

Index :

- `CREATE UNIQUE INDEX manual_payments_reference_in_use_key ON biz.manual_payments USING btree (business_id, method_provider, reference_key) WHERE ((reference_key IS NOT NULL) AND (status = ANY (ARRAY['submitted'::text, 'verified'::text])))`
- `CREATE INDEX manual_payments_status_idx ON biz.manual_payments USING btree (business_id, status, created_at)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.payment_methods

Moyens de paiement direct du commerçant (Orange Money, Mobile Money, code marchand), affichés au client.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `provider` | `text` | non |  |
| `display_name` | `text` | non |  |
| `account_name` | `text` | oui |  |
| `phone_number` | `text` | oui |  |
| `merchant_code` | `text` | oui |  |
| `instructions` | `text` | oui |  |
| `ussd_code` | `text` | oui |  |
| `logo_key` | `text` | oui |  |
| `is_active` | `boolean` | non | `true` |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `updated_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `payment_methods_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `payment_methods_pkey` : `PRIMARY KEY (id)`
- `payment_methods_business_id_id_key` : `UNIQUE (business_id, id)`

Index :

- `CREATE INDEX payment_methods_active_idx ON biz.payment_methods USING btree (business_id, is_active)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.payments

Encaissement rattaché à une vente, déclaré par le commerçant (espèces, mobile money…).

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `sale_id` | `uuid` | non |  |
| `method` | `text` | non |  |
| `amount` | `numeric(14,2)` | non |  |
| `received_by` | `uuid` | non |  |
| `provider_reference` | `text` | oui |  |
| `received_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `payments_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `payments_business_id_sale_id_fkey` : `FOREIGN KEY (business_id, sale_id) REFERENCES biz.sales(business_id, id) ON DELETE CASCADE`
- `payments_received_by_fkey` : `FOREIGN KEY (received_by) REFERENCES core.users(id)`
- `payments_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX payments_business_sale_idx ON biz.payments USING btree (business_id, sale_id)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.products

Produit du catalogue : prix d'achat et de vente, stock courant, seuil d'alerte.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `category_id` | `uuid` | oui |  |
| `name` | `text` | non |  |
| `sku` | `text` | oui |  |
| `barcode` | `text` | oui |  |
| `unit` | `text` | non | `'unite'::text` |
| `purchase_price` | `numeric(14,2)` | non | `0` |
| `sale_price` | `numeric(14,2)` | non |  |
| `current_stock` | `numeric(14,2)` | non | `0` |
| `low_stock_threshold` | `numeric(14,2)` | oui |  |
| `is_active` | `boolean` | non | `true` |
| `image_key` | `text` | oui |  |
| `description` | `text` | oui |  |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `updated_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |

Contraintes :

- `products_business_id_category_id_fkey` : `FOREIGN KEY (business_id, category_id) REFERENCES biz.categories(business_id, id) ON DELETE SET NULL (category_id)`
- `products_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `products_pkey` : `PRIMARY KEY (id)`
- `products_business_id_id_key` : `UNIQUE (business_id, id)`

Index :

- `CREATE INDEX products_business_barcode_idx ON biz.products USING btree (business_id, barcode)`
- `CREATE UNIQUE INDEX products_business_barcode_uq ON biz.products USING btree (business_id, barcode) WHERE (barcode IS NOT NULL)`
- `CREATE INDEX products_business_name_idx ON biz.products USING btree (business_id, name)`
- `CREATE UNIQUE INDEX products_business_sku_uq ON biz.products USING btree (business_id, sku) WHERE (sku IS NOT NULL)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.sale_counters

Compteur par entreprise des numéros de vente, incrémenté de façon atomique (pas de doublon en concurrence).

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `business_id` | `uuid` | non |  |
| `last_number` | `integer` | non |  |

Contraintes :

- `sale_counters_last_number_check` : `CHECK ((last_number >= 0))`
- `sale_counters_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `sale_counters_pkey` : `PRIMARY KEY (business_id)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.sale_items

Ligne de vente : produit, quantité, prix appliqué.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `sale_id` | `uuid` | non |  |
| `product_id` | `uuid` | non |  |
| `product_name_snapshot` | `text` | non |  |
| `unit_price` | `numeric(14,2)` | non |  |
| `unit_cost_snapshot` | `numeric(14,2)` | non |  |
| `quantity` | `numeric(14,2)` | non |  |
| `discount` | `numeric(14,2)` | non | `0` |
| `line_total` | `numeric(14,2)` | non |  |

Contraintes :

- `sale_items_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `sale_items_business_id_product_id_fkey` : `FOREIGN KEY (business_id, product_id) REFERENCES biz.products(business_id, id)`
- `sale_items_business_id_sale_id_fkey` : `FOREIGN KEY (business_id, sale_id) REFERENCES biz.sales(business_id, id) ON DELETE CASCADE`
- `sale_items_pkey` : `PRIMARY KEY (id)`

Index :

- `CREATE INDEX sale_items_sale_idx ON biz.sale_items USING btree (sale_id)`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

### biz.sales

Vente encaissée ; is_offline signale une vente faite hors ligne, qui peut avoir fait passer le stock sous zéro.

RLS : activée et **forcée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `id` | `uuid` | non | `gen_random_uuid()` |
| `business_id` | `uuid` | non |  |
| `customer_id` | `uuid` | oui |  |
| `sale_number` | `text` | non |  |
| `client_request_id` | `text` | oui |  |
| `subtotal` | `numeric(14,2)` | non |  |
| `discount_total` | `numeric(14,2)` | non | `0` |
| `total` | `numeric(14,2)` | non |  |
| `amount_paid` | `numeric(14,2)` | non | `0` |
| `amount_due` | `numeric(14,2)` | non | `0` |
| `status` | `text` | non | `'completed'::text` |
| `sold_by` | `uuid` | non |  |
| `sold_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `created_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `updated_at` | `timestamp(3) without time zone` | non | `CURRENT_TIMESTAMP` |
| `is_offline` | `boolean` | non | `false` |

Contraintes :

- `sales_business_id_customer_id_fkey` : `FOREIGN KEY (business_id, customer_id) REFERENCES biz.customers(business_id, id) ON DELETE SET NULL (customer_id)`
- `sales_business_id_fkey` : `FOREIGN KEY (business_id) REFERENCES core.businesses(id) ON DELETE CASCADE`
- `sales_sold_by_fkey` : `FOREIGN KEY (sold_by) REFERENCES core.users(id)`
- `sales_pkey` : `PRIMARY KEY (id)`
- `sales_business_id_client_request_id_key` : `UNIQUE (business_id, client_request_id)`
- `sales_business_id_id_key` : `UNIQUE (business_id, id)`
- `sales_business_id_sale_number_key` : `UNIQUE (business_id, sale_number)`

Index :

- `CREATE INDEX sales_business_sold_at_idx ON biz.sales USING btree (business_id, sold_at)`
- `CREATE INDEX sales_offline_idx ON biz.sales USING btree (business_id, sold_at) WHERE is_offline`

Politiques RLS :

- `tenant_isolation` — ALL, rôles PUBLIC; USING `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`; WITH CHECK `(business_id = (NULLIF(current_setting('app.business_id'::text, true), ''::text))::uuid)`

Droits :

- `thy_app` : SELECT, INSERT, UPDATE, DELETE
- `thy_admin_app` : aucun
- `thy_readonly` : aucun

## Schéma `public`

standard public schema

### public.schema_migrations

Migrations appliquées, avec leur somme de contrôle (géré par le migrateur).

RLS : **désactivée**

| Colonne | Type | Nul | Défaut |
| --- | --- | --- | --- |
| `name` | `text` | non |  |
| `checksum` | `text` | non |  |
| `applied_at` | `timestamp with time zone` | non | `now()` |

Contraintes :

- `schema_migrations_pkey` : `PRIMARY KEY (name)`

Droits :

- `thy_app` : aucun
- `thy_admin_app` : aucun
- `thy_readonly` : aucun
