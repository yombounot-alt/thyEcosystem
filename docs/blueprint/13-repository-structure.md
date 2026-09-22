# 13 — Structure exacte du dépôt

Couvre le point 23. **Monorepo** (ADR-002) : `pnpm workspaces + Turborepo` pour TypeScript, `Melos` pour Dart.

> Les dossiers marqués **[P0]** sont créés en Phase 0 ; les autres sont créés à la phase indiquée (pas de dossiers vides « au cas où »).

```
thyEcosystem/
├─ .github/
│  ├─ workflows/
│  │  ├─ ci-backend.yml              lint · types · tests · intégration · schéma/RLS · contrat · sécurité   [P0]
│  │  ├─ ci-mobile.yml               analyze · tests · golden · build debug                                [P0]
│  │  ├─ ci-admin.yml                lint · tests · build                                                  [P0]
│  │  ├─ security.yml                CodeQL/Semgrep · gitleaks · Trivy · SBOM · audit deps                 [P0]
│  │  ├─ deploy-staging.yml          image SHA → migrate → api/worker → smoke/E2E                          [P0]
│  │  ├─ deploy-production.yml       environnement protégé, approbation, déploiement progressif            [P0]
│  │  └─ release-mobile.yml          Fastlane/Codemagic, déploiement par pourcentage                       [P0]
│  ├─ CODEOWNERS                     contracts/ · migrations · payments · auth · rbac · infra              [P0]
│  ├─ dependabot.yml                                                                                       [P0]
│  └─ pull_request_template.md       checklist Definition of Done                                          [P0]
│
├─ backend/                          NestJS · TypeScript strict
│  ├─ src/
│  │  ├─ main.api.ts                 HTTP + WebSocket
│  │  ├─ main.worker.ts              files · outbox · planificateur · webhooks
│  │  ├─ main.migrate.ts             job de migration
│  │  ├─ app.api.module.ts · app.worker.module.ts
│  │  │
│  │  ├─ kernel/                     TIER 1 — aucun métier                                                 [P0]
│  │  │  ├─ config/                  schéma d'env (Zod), chargement des secrets, garde « pas de sandbox en prod »
│  │  │  ├─ database/                client Drizzle, TenantTransactionManager (RLS), UnitOfWork, écriture outbox
│  │  │  ├─ events/                  port EventBus, relais outbox, inbox/idempotence, registre de schémas
│  │  │  ├─ queue/                   BullMQ, registre de files, DLQ, planificateur (verrou leader)
│  │  │  ├─ cache/                   Redis, clés namespacées par tenant
│  │  │  ├─ http/                    filtres problem+json, idempotence, pagination, versioning, ETag
│  │  │  ├─ security/                guards (auth, tenant, permissions, entitlements), throttler, crypto, redaction
│  │  │  ├─ observability/           pino, OTel (traces/métriques), health, Sentry
│  │  │  ├─ storage/                 port ObjectStorage + adaptateur S3
│  │  │  ├─ i18n/                    messages serveur, gabarits
│  │  │  ├─ clock/                   horloge injectable (tests)
│  │  │  └─ testing/                 Testcontainers, fabriques de base, utilitaires RLS
│  │  │
│  │  └─ modules/
│  │     │  ─ TIER 2 : moteurs de plateforme ─
│  │     ├─ auth/                    [P0]  otp · sessions · tokens · devices · recovery · anti-abus
│  │     ├─ users/                   [P0]  compte · profil · personas · consentements · app-config
│  │     ├─ businesses/              [P0]  entreprises · lieux · membres · invitations
│  │     ├─ rbac/                    [P0]  rôles · permissions · évaluation · cache
│  │     ├─ subscriptions/           [P0 squelette · P1]  plans · entitlements · quotas · flags
│  │     ├─ notifications/           [P0 base]  préférences · gabarits · canaux · in-app
│  │     ├─ media/                   [P0]  upload présigné · scan · variantes
│  │     ├─ audit/                   [P0]
│  │     ├─ payments/                [P1 fin]   providers/ (sandbox, <psp>) · state-machine/ · ledger/ · reconciliation/ · payouts/
│  │     ├─ ai-gateway/              [P2]  LlmProvider · quotas · journal
│  │     ├─ search/                  [P3]
│  │     ├─ messaging/               [P3]
│  │     ├─ reviews/                 [P3]
│  │     ├─ verification/            [P3]
│  │     ├─ moderation/              [P3]  signalements · cases · actions · litiges
│  │     ├─ engagement/              [P3]  favoris · alertes
│  │     ├─ support/                 [P3]
│  │     ├─ geo/                     [P3–4]
│  │     ├─ partner-api/             [P4]  API keys · webhooks sortants
│  │     │  ─ TIER 3 : modules métier ─
│  │     ├─ business/                [P1]  products/ · inventory/ · contacts/ · sales/ · cash/ · purchases/
│  │     │                                 expenses/ · employees/ · reports/ · sync/
│  │     ├─ ai/                      [P2, P10]  tools/ · pipeline/ · vision/
│  │     ├─ marketplace/             [P3]
│  │     ├─ delivery/                [P4]
│  │     ├─ services/                [P5]
│  │     ├─ immo/                    [P6]
│  │     ├─ jobs/                    [P7]
│  │     ├─ agro/                    [P8]
│  │     ├─ finance/                 [P9]  (THY Money)
│  │     ├─ academy/                 [P10]
│  │     └─ admin-api/               [P0]  contrôleurs /admin/v1/* (guards staff dédiés), un sous-dossier par section
│  │
│  ├─ db/
│  │  ├─ migrations/                 SQL versionné, revu à la main
│  │  ├─ seeds/
│  │  │  ├─ reference/               permissions · rôles système · devises · unités · pays · plans (idempotents, prod-safe)
│  │  │  └─ demo/                    fausses données — bloqué hors dev/staging
│  │  └─ schema-lint/                règles CI : RLS, index tenant, contraintes
│  ├─ test/
│  │  ├─ e2e/                        parcours complets (S1…S9)
│  │  ├─ contract/                   OpenAPI · événements
│  │  ├─ security/                   fuite tenant · matrice rôle×route · IDOR
│  │  └─ load/                       k6
│  ├─ drizzle.config.ts · nest-cli.json · tsconfig*.json · eslint.config.js
│  ├─ .dependency-cruiser.cjs        règles R1–R7                                                          [P0]
│  ├─ Dockerfile                     (api et worker : même image, commandes différentes)
│  └─ package.json
│
├─ admin/                            React + Vite + TypeScript                                             [P0]
│  ├─ src/
│  │  ├─ app/                        routes, shell, guards staff
│  │  ├─ features/                   un dossier par section (users, audit, settings, … ajoutées par phase)
│  │  ├─ components/                 composants + tokens partagés
│  │  ├─ lib/                        client API (généré), auth SSO/MFA, i18n
│  │  └─ main.tsx
│  ├─ index.html · vite.config.ts · package.json
│
├─ mobile/                           workspace Melos (Flutter)                                             [P0]
│  ├─ melos.yaml · pubspec.yaml · analysis_options.yaml
│  ├─ app/                           shell
│  │  ├─ lib/
│  │  │  ├─ main_dev.dart · main_staging.dart · main_prod.dart    (flavors)
│  │  │  ├─ bootstrap/               init, DI, Sentry, flags
│  │  │  ├─ module_registry/         ThyModule, enregistrement des modules
│  │  │  ├─ navigation/              NavigationPolicy, routes racines, deep links
│  │  │  └─ shell/                   barre de navigation, contexte actif, indicateur de sync
│  │  ├─ android/ · ios/             configurations par flavor
│  │  └─ pubspec.yaml
│  └─ packages/
│     ├─ thy_core/                   réseau, session, sécurité, erreurs, config, flags, entitlements
│     ├─ thy_design_system/          tokens générés, thèmes, composants, galerie Widgetbook
│     ├─ thy_api/                    client OpenAPI généré
│     ├─ thy_sync/                   base locale, file de commandes, conflits                               [P1]
│     ├─ thy_l10n/                   ARB fr/en, formateurs
│     ├─ thy_engines/                chat, avis, média, carte, notifications, badge vérification, recherche [P3]
│     └─ features/
│        ├─ account/  home/                                                                                [P0]
│        ├─ business/                                                                                      [P1]
│        ├─ ai/                                                                                            [P2]
│        ├─ marketplace/ delivery/ services/ immo/ jobs/ agro/ money/ academy/                             [P3–P10]
│
├─ shared/                           sources de vérité inter-piles
│  ├─ api-contracts/                 openapi.snapshot.json · events/*.schema.ts · error-codes.ts
│  ├─ design-tokens/                 tokens/*.json · style-dictionary.config · sorties générées (Dart/CSS)
│  ├─ permissions/                   catalogue permissions & entitlements (→ constantes TS et Dart générées)
│  └─ config-presets/                eslint · tsconfig · prettier
│
├─ infra/
│  ├─ docker/                        compose.dev.yml · postgres/init (extensions, rôles) · otel-collector.yml
│  ├─ terraform/                     modules/ · envs/{staging,production}/                                  [P0 staging]
│  └─ scripts/                       bootstrap dev, génération de clients, vérifications
│
├─ docs/
│  ├─ blueprint/                     ce dossier (référence de départ)
│  ├─ adr/                           décisions d'architecture numérotées
│  ├─ threat-models/                 un fichier par module
│  ├─ runbooks/                      un par alerte
│  ├─ ARCHITECTURE.md · DATABASE.md · API.md · SECURITY.md · DEPLOYMENT.md · TESTING.md
│  └─ product/                       glossaire, parcours, règles métier
│
├─ tools/                            scripts de dépôt (génération de docs DB, vérifications d'architecture)
├─ README.md · CONTRIBUTING.md · CHANGELOG.md
├─ package.json · pnpm-workspace.yaml · turbo.json
└─ .editorconfig · .gitignore · .gitleaks.toml · .nvmrc · .env.example
```

## Règles associées
- **Import inter-modules** : uniquement `modules/<x>/contracts/**` (vérifié CI).
- **Un module = un schéma PG** (`db/migrations/<schema>/…`) ; les tables portent le schéma dans leur définition.
- **Aucun fichier `.env` réel commité** ; `.env.example` documente chaque variable sans valeur sensible.
- **Génération** : `pnpm gen` (OpenAPI → clients Dart/TS ; tokens → Dart/CSS ; permissions → constantes) — les fichiers générés sont **commités** (revue des diffs de contrat) mais jamais édités à la main.
- **Conventions de nommage** : `snake_case` DB, `kebab-case` fichiers TS, `snake_case` fichiers Dart, `SCREAMING_SNAKE` événements/permissions-codes de statut.

## Outillage local à installer en Phase 0 (H6)
`pnpm` (via Corepack), **JDK 17** + Android SDK/émulateur, Docker Desktop (WSL2) déjà présent, Node LTS déjà présent, Flutter déjà présent (vérifier version/`flutter doctor`), CLI de fournisseur cloud, `gitleaks`, `k6`. **iOS** : compilation via CI macOS uniquement (pas de Mac local).
