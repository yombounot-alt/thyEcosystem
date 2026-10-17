# Décisions d'architecture (ADR)

Un fichier par décision : contexte, options, décision, conséquences, critère de remise en cause,
puis un **constat de mise en œuvre** vérifié dans le code. Quand le code s'écarte d'une décision,
l'écart est écrit dans l'ADR concernée plutôt que caché.

**Statuts** :

- **Acceptée** : validée par l'utilisateur ; ADR-001 à 018 l'ont été avec le blueprint le
  2026-09-22.
- **Amendée** : une décision ultérieure en remplace une partie, et le lien est indiqué.
- **Non implémentée** : acceptée, mais rien n'est encore construit.
- **Constatée, à valider** : choix fait pendant l'implémentation, qui n'a pas encore été validé.

## Nouvelle décision

Copier une ADR existante et prendre le numéro suivant (`0023-titre-court.md`). Une décision
validée ne se réécrit pas : on en crée une nouvelle qui l'amende, et on ajoute le lien des deux
côtés.

## Registre

| ADR                                                                   | Décision                                                     | Statut                                                |
| --------------------------------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| [001](0001-style-d-architecture-backend.md)                           | Monolithe modulaire NestJS                                   | Acceptée — sans processus `worker` à ce jour          |
| [002](0002-organisation-du-depot.md)                                  | Monorepo pnpm + Turborepo + Melos                            | Acceptée                                              |
| [003](0003-acces-aux-donnees-et-migrations.md)                        | Accès aux données et migrations                              | Amendée par 018                                       |
| [004](0004-isolation-multi-tenant.md)                                 | Multi-tenant : `business_id` + RLS forcée                    | Acceptée                                              |
| [005](0005-evenements-et-taches-asynchrones.md)                       | Outbox transactionnelle                                      | Amendée par 022                                       |
| [006](0006-architecture-et-etat-cote-flutter.md)                      | Riverpod + go_router, paquets Melos                          | Acceptée                                              |
| [007](0007-base-locale-mobile-et-synchronisation-offline.md)          | Drift + journal de commandes                                 | Non implémentée — file de ventes hors ligne seulement |
| [008](0008-moteur-de-recherche.md)                                    | PostgreSQL FTS + `pg_trgm`                                   | Non implémentée                                       |
| [009](0009-temps-reel.md)                                             | Socket.IO                                                    | Non implémentée                                       |
| [010](0010-authentification-construire-ou-acheter.md)                 | Authentification construite dans NestJS                      | Amendée par 020 — écart HS256                         |
| [011](0011-paiements-abstraction-grand-livre-absence-de-custody.md)   | Paiements : PSP abstrait, grand livre, aucune garde de fonds | Non implémentée                                       |
| [012](0012-hebergement-cloud-et-region.md)                            | GCP Cloud Run, `europe-west1`                                | Acceptée — Terraform jamais appliqué                  |
| [013](0013-llm-fournisseur-et-orchestration.md)                       | LLM derrière un port, choisi par évaluation                  | Non implémentée (Phase 2)                             |
| [014](0014-cartographie-et-geocodage.md)                              | MapLibre + `GeoProvider`                                     | Non implémentée (Phase 3)                             |
| [015](0015-administration-web.md)                                     | Admin React + Vite + TanStack                                | Acceptée                                              |
| [016](0016-identifiants-et-representation-de-l-argent.md)             | UUIDv7, argent en entiers d'unités mineures                  | Acceptée — **écarts UUIDv4, `numeric`, `timestamp`**  |
| [017](0017-observabilite.md)                                          | Sentry + OpenTelemetry                                       | Acceptée — inactive sans configuration                |
| [018](0018-decouverte-de-code-existant-strategie-de-consolidation.md) | Un ORM par module, identité centrale                         | Acceptée                                              |
| [019](0019-stockage-objet-compatible-s3-rustfs-en-local-et-en-ci.md)  | RustFS en local et en CI                                     | Acceptée                                              |
| [020](0020-authentification-du-staff-comptes-thy-et-totp.md)          | Staff : comptes THY + TOTP                                   | Acceptée                                              |
| [021](0021-contrat-app-api-par-test-plutot-que-client-genere.md)      | Test de contrat app ↔ API                                    | Acceptée                                              |
| [022](0022-relais-doutbox-sur-postgresql.md)                          | Relais d'outbox sur PostgreSQL                               | **Constatée, à valider**                              |

## Écarts à résoudre

Ces écarts entre décision et code ne bloquent pas la Phase 0. Chacun doit être corrigé, ou
accepté par une nouvelle ADR, avant l'échéance indiquée.

| Écart                                                                 | ADR | Avant                                             |
| --------------------------------------------------------------------- | --- | ------------------------------------------------- |
| Montants `numeric(14,2)` sans devise par ligne dans `biz`             | 016 | Module Money / premier paiement réel              |
| Dates `timestamp(3)` sans fuseau dans `biz`                           | 016 | Module Money / premier paiement réel              |
| Identifiants UUIDv4 au lieu d'UUIDv7                                  | 016 | Synchronisation offline (ids générés côté client) |
| JWT HS256 (secret partagé) au lieu d'une signature asymétrique + JWKS | 010 | Second service qui vérifie les jetons             |
| Règles de dépendances entre modules non vérifiées en CI               | 001 | Deuxième module porté                             |
| Relais d'outbox : choix à valider                                     | 022 | Prochaine revue d'architecture                    |

## Décisions mineures

Défauts proposés par le blueprint, modifiables sans débat. La dernière colonne indique ce qui est
réellement en place.

| Sujet                  | Défaut proposé                                             | En place (2026-10-17)                                                                                                       |
| ---------------------- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Validation API         | Zod ; repli class-validator                                | **class-validator** (+ class-transformer)                                                                                   |
| Format d'erreur        | RFC 9457 `application/problem+json` + `code` stable        | `{ error: { code, message, details?, requestId } }` en `application/json` ; `code` stable                                   |
| Pagination             | Curseur (keyset), jamais `OFFSET` sur les listes chaudes   | Curseur opaque (keyset)                                                                                                     |
| Logs                   | pino JSON, redaction déclarative                           | pino JSON avec redaction                                                                                                    |
| Documentation API      | OpenAPI 3.1 générée du code, snapshot + diff cassant en CI | OpenAPI **3.0** générée du code (`docs/api/openapi.json`), dérive bloquée en CI ; pas de détection des changements cassants |
| Client API mobile      | Généré depuis OpenAPI                                      | Écrit à la main + test de contrat ([ADR-021](0021-contrat-app-api-par-test-plutot-que-client-genere.md))                    |
| Réseau mobile          | Dio + intercepteurs                                        | Dio                                                                                                                         |
| Modèles Dart           | freezed + json_serializable                                | Classes écrites à la main                                                                                                   |
| Lint TS / Dart         | ESLint strict + `dependency-cruiser` / analyse stricte     | ESLint `strictTypeChecked` ; `flutter analyze` ; pas de `dependency-cruiser`                                                |
| Feature flags          | Table + cache maison                                       | Table `ops.feature_flags`, sans cache ; gérée depuis l'admin                                                                |
| Vidéo Academy          | Plateforme HLS externe                                     | —                                                                                                                           |
| Analytics produit      | Événements serveur + PostHog ; Metabase                    | —                                                                                                                           |
| E-mail transactionnel  | Fournisseur interchangeable (`EmailProvider`)              | — (aucun envoi d'e-mail dans le code ; le conteneur Mailpit local n'est pas utilisé)                                        |
| Génération PDF (reçus) | Côté serveur + reçu partagé côté mobile                    | —                                                                                                                           |
| Convention commits     | Conventional Commits + changelog automatisé                | commitlint en hook `commit-msg` local (pas en CI) ; [CHANGELOG.md](../../CHANGELOG.md) amorcé depuis l'historique           |
| Branches               | Trunk-based, branches courtes, `main` protégée             | Commits directs sur `main` ; la protection de branche ne peut pas être vérifiée d'ici                                       |
