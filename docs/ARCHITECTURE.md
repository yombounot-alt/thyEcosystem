# Architecture (état réel)

Ce document décrit **ce qui existe dans le code** (Phase 0). La cible à long terme est dans le
[blueprint](blueprint/README.md) ; les décisions et leurs écarts sont dans les [ADR](adr/README.md).

## Vue d'ensemble

```
App Flutter (mobile/app) ──HTTPS /api/v1──┐
                                          ├── API NestJS (backend, un processus) ── PostgreSQL 17 + PostGIS
Console admin (admin/) ───HTTPS /admin/v1─┘        │                                (RLS forcée)
                                                   ├── Redis (limitation de débit, cache des droits et de l'état des comptes)
                                                   ├── Stockage objet S3 (RustFS en local, Cloud Storage visé)
                                                   └── Sentry / OpenTelemetry (si configurés)
```

Un seul dépôt ([ADR-002](adr/0002-organisation-du-depot.md)) :

| Dossier                             | Contenu                                                                          |
| ----------------------------------- | -------------------------------------------------------------------------------- |
| `backend/`                          | API NestJS (ESM), migrateur SQL, CLI d'exploitation                              |
| `admin/`                            | Console d'administration React (staff THY)                                       |
| `mobile/app/`                       | Application Flutter (aujourd'hui : le module Business)                           |
| `mobile/packages/thy_core`          | Socle de l'app (contrat de module, stockage local, réseau…), sans fonctionnalité |
| `mobile/packages/thy_design_system` | Thème et composants, tokens générés                                              |
| `shared/design-tokens`              | Source unique des couleurs (`tokens.json`) → Dart + CSS                          |
| `shared/config-presets`             | ESLint, Prettier et tsconfig communs                                             |
| `infra/`                            | Docker local, Terraform GCP (jamais appliqué), scripts                           |
| `docs/`                             | Blueprint, plans, ADR, threat models, runbooks, référence                        |

## Backend

### Processus

Un monolithe modulaire ([ADR-001](adr/0001-style-d-architecture-backend.md)) avec deux points
d'entrée :

- `src/main.ts` : l'API HTTP. Elle **applique aussi les migrations en attente au démarrage** (verrou consultatif, donc sûr avec plusieurs instances), et le relais d'outbox y tourne ([ADR-022](adr/0022-relais-doutbox-sur-postgresql.md)).
- `src/database/migrate-cli.ts` : applique `backend/migrations/*.sql`. Ces migrations sont
  forward-only, protégées par une somme de contrôle et un verrou consultatif.

Il n'y a pas encore de processus `worker`. `src/instrumentation.ts` est chargé par `--import` avant
l'application, pour OpenTelemetry.

### Kernel (`src/kernel/`)

| Dossier / fichier   | Rôle                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------ |
| `config/`           | Configuration typée, validée au démarrage ; la production refuse de démarrer avec un réglage dangereux |
| `db/`               | `Db` : pool `pg`, `tx()`, `withTenant()` qui pose `app.user_id` / `app.business_id`                    |
| `auth/`             | Jetons d'accès (JWT), gardes globales, permissions, état du compte (suspendu…)                         |
| `security/`         | argon2id, HMAC, empreintes de jetons, comparaisons à temps constant                                    |
| `events/`           | Outbox transactionnelle et son relais                                                                  |
| `notifications/`    | Ports SMS et push (adaptateurs « console » en développement)                                           |
| `storage/`          | Port de stockage : adaptateur disque (dev) ou S3                                                       |
| `redis/`            | Client Redis                                                                                           |
| `observability/`    | Sentry (données personnelles filtrées) et rapport d'erreurs                                            |
| `filters/`          | Format d'erreur unique `{ error: { code, message, details?, requestId } }`                             |
| `infra.services.ts` | Audit, idempotence (`Idempotency-Key`), outbox                                                         |
| `logger.ts`         | Journaux pino JSON avec masquage des champs sensibles                                                  |

### Modules (`src/modules/`)

Toutes les routes publiques sont préfixées par `/api/v1`.

| Module          | Routes                                                              | Rôle                                                                                                                |
| --------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `auth`          | `/auth/*`                                                           | Connexion par OTP SMS, rafraîchissement, déconnexion                                                                |
| `users`         | `/me`, `/me/businesses`                                             | Profil et entreprises de l'utilisateur                                                                              |
| `businesses`    | `/businesses*`, `/me/invitations*`                                  | Entreprises, activation, membres, invitations                                                                       |
| `subscriptions` | `/businesses/{id}/subscription`, `/me/feature-flags`                | Offre, droits et limites ; feature flags de l'utilisateur                                                           |
| `notifications` | `/me/notifications*`, `/me/notification-preferences`, `/me/devices` | Notifications in-app, préférences, jetons push                                                                      |
| `business`      | `/products`, `/sales`, `/customers`, `/payments`, `/dashboard`…     | Module Business porté. Routes « à plat » qui visent l'entreprise active du jeton (`POST /businesses/{id}/activate`) |
| `admin`         | `/admin/v1/*` (hors préfixe `/api/v1`)                              | Console staff ([ADR-020](adr/0020-authentification-du-staff-comptes-thy-et-totp.md)), hors contrat OpenAPI public   |

Le détail des routes publiques est dans [API.md](API.md) et `docs/api/openapi.json`.

### Traitement d'une requête

1. `helmet`, CORS si configuré, `trust proxy` (derrière Cloud Run).
2. Gardes globales, dans cet ordre : `AuthGuard` (jeton) → `RateLimitGuard` (Redis) →
   `AccessGuard`. Une route est **refusée par défaut** si elle ne déclare pas `@Public()`,
   `@Authenticated()` ou `@RequirePermission(...)`.
3. Validation des DTO (`class-validator`) : un champ non déclaré est refusé (`forbidNonWhitelisted`).
4. Le service ouvre une transaction `withTenant()` : la RLS PostgreSQL filtre alors les lignes
   ([ADR-004](adr/0004-isolation-multi-tenant.md)).
5. Les effets vers d'autres modules passent par l'outbox, dans la même transaction.
6. Toute erreur sort au format unique, avec le `requestId`.

### Données

PostgreSQL, un schéma par domaine : `core`, `ops`, `ntf`, `sub`, et `biz` pour Business. Le module
Business lit et écrit par un client Prisma (requêtes seulement). Tout le reste passe par du SQL
écrit à la main ([ADR-018](adr/0018-decouverte-de-code-existant-strategie-de-consolidation.md)).
Référence complète, générée depuis la base : [DATABASE.md](DATABASE.md).

Quatre rôles PostgreSQL :

- `thy_migrator`, propriétaire du schéma, utilisé seulement par le migrateur et les CLI ;
- `thy_app` (API) et `thy_admin_app` (console), soumis à la RLS ;
- `thy_readonly`, sans aucun droit pour l'instant.

## Application mobile

- Flutter 3.47, Riverpod 3, go_router, Dio ([ADR-006](adr/0006-architecture-et-etat-cote-flutter.md)).
- Le shell découvre les modules par un registre (`lib/navigation/module_registry.dart`).
  Business est le seul module (`lib/modules/business/`) ; ses écrans sont dans `lib/features/`.
- Variantes Android `dev` / `staging` / `prod`. L'URL de l'API est obligatoire hors `dev`.
  L'identifiant d'app, provisoire (`com.thyecosystem.app`), est défini par une seule constante
  dans `android/app/build.gradle.kts`.
- Ventes hors ligne : une file locale est rejouée sans risque de doublon
  ([ADR-007](adr/0007-base-locale-mobile-et-synchronisation-offline.md)).
- Contrat avec l'API vérifié par `test/api_contract_test.dart` ([ADR-021](adr/0021-contrat-app-api-par-test-plutot-que-client-genere.md)).
- Textes en ARB, français seulement (l'anglais est préparé mais pas activé).

## Console d'administration

React 19, Vite, TanStack Query et TanStack Router. La console est servie sur la même origine que
`/admin/v1` (proxy Vite en développement). La session vit dans un cookie HttpOnly, et le jeton
anti-CSRF reste en mémoire. Les écrans masquent ce que le rôle n'autorise pas, mais c'est le serveur
qui décide (403 sinon). Voir [ADR-020](adr/0020-authentification-du-staff-comptes-thy-et-totp.md).

## Ce qui n'existe pas encore

Processus `worker`, temps réel, recherche, paiements par prestataire, IA, cartographie,
synchronisation offline générale, envoi d'e-mails, fournisseur SMS réel, push FCM réel, et tout
déploiement (Terraform jamais appliqué). Les modules Marketplace, Services, Delivery, Immo, Jobs,
Academy, Agro, Money et AI ne sont pas commencés. Feuille de route :
[blueprint 14](blueprint/14-roadmap-risks.md).
