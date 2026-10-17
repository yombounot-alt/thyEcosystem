# Threat model — isolation entre entreprises (multi-tenant)

- **Périmètre** : empêcher qu'un utilisateur d'une entreprise voie ou modifie les données d'une
  autre.
- **Décision** : [ADR-004](../adr/0004-isolation-multi-tenant.md).
- **Code** : `backend/src/kernel/db/` (`withTenant`), `backend/src/kernel/auth/guards.ts`,
  `backend/migrations/` (politiques). État réel des politiques et des droits :
  [DATABASE.md](../DATABASE.md).
- **Tests** : `backend/test/kernel/rls.e2e-spec.ts`, `rbac.e2e-spec.ts`, `team.e2e-spec.ts`.
- **Révisé le** : 2026-10-17.

## Défense en profondeur

1. **Appartenance vérifiée en base** : l'entreprise active d'un jeton n'est émise que si
   l'utilisateur en est membre (`POST /businesses/{id}/activate`). Une valeur envoyée par le
   client n'est jamais crue.
2. **Droits** : chaque route déclare un droit (`@RequirePermission`), et l'accès est refusé par
   défaut.
3. **RLS PostgreSQL forcée** : l'API se connecte en `thy_app` (`NOBYPASSRLS`). Les tables tenant
   filtrent sur `app.business_id`, posé par `withTenant()` dans la transaction. Sans contexte,
   aucune ligne n'est visible : le refus est le comportement par défaut.
4. **Clés étrangères composites** `(business_id, id)` dans `biz` : une ligne ne peut pas référencer
   la ligne d'une autre entreprise, même si le code se trompe d'identifiant.

## Menaces et mesures

| #   | Menace                                                               | Mesure                                                                                                                                               | Reste                                                                                                                                                                                      |
| --- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| T1  | Requête oubliant le filtre `business_id`                             | RLS forcée sur les tables de `biz`, `ntf` et `sub` ; test « aucune ligne sans contexte »                                                             | Voir T5                                                                                                                                                                                    |
| T2  | Identifiant d'une autre entreprise passé dans l'URL ou le corps      | RLS ; FK composites ; tests de fuite entre deux entreprises                                                                                          | —                                                                                                                                                                                          |
| T3  | Rôle applicatif capable de contourner la RLS                         | `thy_app` et `thy_admin_app` en `NOBYPASSRLS` ; la production refuse que l'admin utilise l'URL de l'app ou du migrateur                              | **Le processus API détient aussi `MIGRATOR_DATABASE_URL`** : il applique les migrations à son démarrage. Une compromission de l'API donne donc un accès qui contourne la RLS. Voir écart 3 |
| T4  | Contexte d'une requête précédente réutilisé par la connexion du pool | `SET LOCAL` (`set_config(..., true)`), limité à la transaction                                                                                       | —                                                                                                                                                                                          |
| T5  | **Tables sans RLS lisibles par `thy_app`**                           | Voir ci-dessous                                                                                                                                      | **Écart**                                                                                                                                                                                  |
| T6  | Membre retiré qui garde l'accès                                      | L'appartenance est **relue en base à chaque requête** (`AccessGuard`) ; seul le lien rôle → droits est mis en cache (5 min, rôles système immuables) | Testé : « retirer un membre coupe son accès immédiatement » (`team.e2e-spec.ts`)                                                                                                           |
| T7  | Invitation détournée                                                 | Pas de jeton dans un lien : l'invitation est acceptée dans l'app par le titulaire du numéro vérifié                                                  | —                                                                                                                                                                                          |

### T5 — tables sans RLS

[DATABASE.md](../DATABASE.md) montre **19 tables sans RLS**. Ce sont les tables globales, sans
`business_id` : `core.users`, `core.refresh_tokens`, `core.otp_challenges`, `core.login_events`,
les tables de rôles et de droits, les tables staff, `ops.*` (dont `audit_logs`, `outbox_events`,
`idempotency_keys`) et les catalogues de `sub` (`plans`, `entitlements`, `plan_entitlements`).

Pour ces tables, **seul le code applicatif protège les lignes** : `thy_app` peut lire tous les
utilisateurs et tout le journal d'audit si une requête est mal écrite. Depuis la migration `0012`,
il ne peut plus modifier ni effacer l'historique (`ops.audit_logs`, `core.login_events`,
`sub.subscription_events` : `SELECT` et `INSERT` seulement). Il gardait auparavant `UPDATE` et
`DELETE`, ce qu'a révélé la génération de [DATABASE.md](../DATABASE.md). C'est acceptable pour les
catalogues (`plans`, `permissions`…), moins pour `core.users`, `core.refresh_tokens` et
`ops.audit_logs`, qui contiennent des données personnelles.

## Écarts à traiter

1. **Étendre le test de fuite** (`rls.e2e-spec.ts`, aujourd'hui limité à `biz`) : une liste
   explicite des tables globales autorisées sans RLS, et l'échec du test pour toute autre table
   sans RLS forcée, quel que soit le schéma. Un nouveau schéma sera alors couvert automatiquement.
2. **Évaluer la RLS sur `core.users` et `core.refresh_tokens`** (`id = app.user_id`), en gardant
   les chemins d'authentification qui doivent lire avant de connaître l'utilisateur.
3. **Retirer `MIGRATOR_DATABASE_URL` du service `api`** : laisser les migrations au seul job
   `migrate` (déjà prévu dans Terraform) et supprimer leur exécution au démarrage de l'API. Les
   CLI d'exploitation (`staff:create`) gardent la connexion du migrateur, lancée à la main.
