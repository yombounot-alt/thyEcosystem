# Plan détaillé — PHASE 0 : Foundation

> Statut : **proposition, en attente de ton feu vert avant le premier commit de code.**
> Pré-requis satisfait : blueprint validé ([docs/blueprint/README.md](../blueprint/README.md)), décisions D1–D11 adoptées, charte de marque dérivée du logo ([docs/brand/README.md](../brand/README.md)).
> Référence transverse : [02-architecture.md](../blueprint/02-architecture.md), [13-repository-structure.md](../blueprint/13-repository-structure.md).

---

## 1. Objectif et non-objectif

**Objectif** : poser les fondations techniques et de confiance — dépôt, CI/CD, infra staging, kernel backend, identité/auth, tenancy/RBAC, moteurs de base (subscriptions squelette, notifications, media), design system, shells Flutter + admin, documentation. **Zéro logique métier** (pas de produit, pas de vente).

**Critère de sortie unique et vérifiable** : un utilisateur peut s'inscrire par OTP sur un **appareil réel**, créer une entreprise, inviter un second membre avec un rôle, et tout ceci est **prouvé** par des tests de fuite tenant au vert, une CI complète verte, et une observabilité active — en **staging**, pas seulement en local.

**Hors périmètre** (rappel) : Business, Marketplace, IA, paiements de commandes, tout module métier.

---

## 2. Pré-requis d'outillage (à faire en premier, avant L0.1)

| Action                                       | Détail                                                                                                                                                                                            |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Installer **pnpm**                           | `corepack enable && corepack prepare pnpm@latest --activate`                                                                                                                                      |
| Installer **JDK 17** + Android SDK/émulateur | requis pour build Android/Flutter                                                                                                                                                                 |
| Vérifier `flutter doctor`                    | version Flutter déjà présente à `D:\src\flutter` — confirmer stable + licences Android acceptées                                                                                                  |
| Compte(s) cloud                              | **GCP retenu (ADR-012).** Créer 3 **projets GCP séparés** dev/staging/prod (facturation, IAM, API activées : Cloud Run, Cloud SQL, Memorystore, Cloud Storage, Secret Manager, Artifact Registry) |
| Comptes fournisseurs (sandbox)               | 2 fournisseurs SMS, Firebase (3 projets : dev/staging/prod), Sentry, un PSP (accès sandbox)                                                                                                       |
| `gh` CLI                                     | déjà présent (`git` détecté) ; créer le dépôt distant (GitHub) si ce n'est pas déjà fait — **le dossier n'est pas encore un dépôt git**                                                           |

**Décision restante avant L0.4** : la **région GCP** (latence réelle depuis les réseaux mobiles ouest-africains à mesurer ; candidates `europe-west1`/`europe-west4`, aucune région GCP en Afrique de l'Ouest à ce jour) — ne bloque pas le démarrage, un choix par défaut (`europe-west1`) sera pris et documenté en ADR si aucune mesure n'est disponible à temps.

---

## 3. Découpage en lots

Ordre d'exécution **recommandé** (respecte les dépendances techniques). Les lots marqués **[//]** peuvent être menés en parallèle par deux personnes si l'équipe le permet ; sinon, séquentiel.

### L0.0 — Initialisation du dépôt

- `git init`, structure racine (`pnpm-workspace.yaml`, `turbo.json`, `melos.yaml`), `.gitignore`, `.editorconfig`, `.env.example`, `.gitleaks.toml`, `LICENSE` (à définir : propriétaire, privé).
- Premier commit : **squelette de dossiers vides avec `.gitkeep`** reflétant [13-repository-structure.md](../blueprint/13-repository-structure.md), sans code.
- **Sortie** : dépôt initialisé, poussé sur le remote choisi.

### L0.1 — Dépôt & outillage

- `package.json` racine, workspaces pnpm, Turborepo (`turbo.json` : pipelines `lint`, `test`, `build`).
- Config partagée : `shared/config-presets/` (ESLint, Prettier, tsconfig de base).
- Melos (`mobile/melos.yaml`) + `analysis_options.yaml` partagé.
- Hooks : `gitleaks` en pre-commit (Husky ou lefthook), Conventional Commits (`commitlint`).
- **Dépend de** : L0.0. **Sortie** : `pnpm install` et `melos bootstrap` fonctionnent, lint/format exécutables (même à vide).

### L0.2 — Environnement local

- `infra/docker/compose.dev.yml` : PostgreSQL 17 + PostGIS, Redis, MinIO (S3 local), Mailpit (SMTP fake), collecteur OTel.
- `infra/docker/postgres/init/` : création des rôles (`thy_migrator`, `thy_app`, `thy_readonly`), extensions (`postgis`, `pg_trgm`, `unaccent`, `citext`, `btree_gist`).
- Scripts `infra/scripts/` : bootstrap dev en une commande, reset DB.
- **Dépend de** : L0.1. **Sortie** : `docker compose up` démarre tout ; connexion PG avec PostGIS vérifiée.

### L0.3 — CI/CD squelette

- `.github/workflows/ci-backend.yml`, `ci-mobile.yml`, `ci-admin.yml`, `security.yml` (CodeQL/Semgrep, gitleaks, Trivy, SBOM, audit deps) — **exécutables dès qu'il y a du code**, même minimal.
- `CODEOWNERS`, `pull_request_template.md` (checklist Definition of Done).
- Environnement GitHub `production` protégé (règle d'approbation) créé **dès maintenant**, vide de contenu.
- **Dépend de** : L0.1. **Sortie** : une PR vide déclenche tous les workflows en vert.

### L0.5 — Kernel backend _(avant L0.4 infra — le kernel doit exister pour valider l'infra avec une vraie appli)_

- `backend/` : NestJS, structure `kernel/*` complète ([13 §backend](../blueprint/13-repository-structure.md)) :
  - `config/` : schéma Zod d'environnement, refus de démarrage si invalide ou si `SandboxProvider` actif hors dev/staging.
  - `database/` : client **Drizzle**, `TenantTransactionManager` (`SET LOCAL app.business_id/user_id`), `UnitOfWork`, écriture outbox transactionnelle.
  - `events/` : port `EventBus`, relais outbox → BullMQ, table `processed_events`, schémas Zod d'événements.
  - `queue/` : BullMQ, registre de files, DLQ, verrou leader pour le planificateur.
  - `cache/` : client Redis, clés namespacées.
  - `http/` : filtre `problem+json`, intercepteur idempotence, pagination curseur, versioning `/api/v1`.
  - `security/` : guards (`AuthGuard`, `TenantGuard`, `PermissionsGuard`, `EntitlementGuard`), throttler, crypto (Argon2id, HMAC), redaction de logs.
  - `observability/` : pino + OTel, `/health/live`, `/health/ready`, intégration Sentry.
  - `storage/` : port `ObjectStorage` + adaptateur S3/MinIO.
  - `i18n/`, `clock/` (horloge injectable), `testing/` (Testcontainers PG+PostGIS, Redis, MinIO).
- **Spike S1 (2 jours, ADR-003)** exécuté ici : valider Drizzle + `geography(Point)` + `ST_DWithin` + RLS `SET LOCAL` en transaction + FK composites + migration expand/contract. **Repli documenté vers Kysely si échec.**
- `db/migrations/` : premières migrations (rôles, extensions déjà en L0.2, tables `core.*` de base arrivent avec L0.6/L0.7).
- `dependency-cruiser` : règles R1–R7 configurées et **vertes sur un kernel vide de modules**.
- **Dépend de** : L0.2, L0.3. **Sortie** : `api`, `worker`, `migrate` démarrent, se connectent à PG/Redis/MinIO, `/health` répond, outbox testée par un événement de démonstration bout en bout.

### L0.4 — Infra staging (IaC) **[//]** peut démarrer en parallèle de L0.5 par une autre personne

- `infra/terraform/` (provider `google`) : réseau (VPC + connecteur serverless), **Cloud Run** (`api`, `worker`), **Cloud SQL for PostgreSQL** (extension PostGIS activée), **Memorystore for Redis** (`noeviction`), **Cloud Storage** (bucket privé, accès via API compatible S3), **Secret Manager**, **Artifact Registry**, **Cloud CDN + Cloud Armor** (WAF), **Cloud Logging/Monitoring** de base.
- Environnement **staging** uniquement pour l'instant (prod = squelette, pas de trafic).
- Observabilité : Sentry projet staging (Cloud Logging/Monitoring en complément immédiat, migration vers Grafana/Tempo/Loki prévue plus tard — ADR-017).
- **Dépend de** : projets GCP créés (§2). **Sortie** : `terraform apply` provisionne staging ; un déploiement du kernel L0.5 (image vide) sur Cloud Run répond sur `/health`.

### L0.6 — Identité (`auth`, `users`)

- Tables `core.users`, `user_credentials`, `user_profiles`, `sessions`, `devices`, `otp_challenges`.
- Flux OTP complet ([04-identity-access.md §2](../blueprint/04-identity-access.md)) : demande, envoi (2 fournisseurs SMS + repli), vérification, anti-abus (limites multi-clés, attestation d'appareil), création de session, JWT ES256/EdDSA + JWKS, refresh opaque avec rotation et détection de réutilisation.
- `GET/PATCH /me`, déconnexion globale, gestion des appareils/sessions.
- `audit` : `ops.audit_logs` + décorateur d'audit sur actions sensibles.
- **Dépend de** : L0.5. **Sortie** : inscription/connexion OTP fonctionnelle en local **et en staging sur appareil réel** (test S3 délivrabilité SMS commencé ici, en continu).

### L0.7 — Tenancy & RBAC

- Tables `core.businesses`, `business_locations`, `business_members`, `business_invitations`, `roles`, `permissions`, `role_permissions`, `staff_users`.
- `businesses` : création, lieux, invitations (jeton haché, expirant, usage unique).
- `rbac` : évaluation permission (chaîne USER→BUSINESS→ROLE→PERMISSION), cache Redis TTL 60 s invalidé par `MEMBER_ROLE_CHANGED`, rôles système + rôles personnalisés (entitlement).
- **RLS activée** sur toutes les tables tenant créées à ce stade + politique `FORCE`.
- **Tests de fuite tenant générés** (lint de schéma + suite d'isolation, [04 §5](../blueprint/04-identity-access.md), [10 §3](../blueprint/10-testing.md)) — **bloquants en CI dès ce lot**.
- **Dépend de** : L0.6. **Sortie** : créer une entreprise, inviter un membre, changer son rôle, vérifier qu'un autre tenant ne voit rien — **prouvé par tests automatisés**, pas seulement manuellement.

### L0.8 — Plateforme de base

- `subscriptions` : squelette (`plans`, `entitlements`, `plan_entitlements`, `subscriptions`) + plan `FREE` par défaut à la création d'entreprise ; `feature_flags`.
- `notifications` : in-app + push FCM (3 projets dev/staging/prod déjà créés en §2), préférences, gabarits, `notification_deliveries`.
- `media` : upload présigné, statut `PENDING→AVAILABLE|REJECTED`, scan antivirus (a minima un adaptateur simple, à renforcer), variantes de base.
- **Dépend de** : L0.7. **Sortie** : une entreprise créée reçoit une notification de bienvenue ; un avatar peut être uploadé et affiché.

### L0.9 — Design system

- `shared/design-tokens/` : primitifs + sémantiques **conformes à [docs/brand/README.md](../brand/README.md)** (§3–4), Style Dictionary → sorties Dart (`ThemeExtension`) et CSS (admin).
- `mobile/packages/thy_design_system/` : thèmes clair/sombre, composants de base (boutons, champs, cartes, badges dont **badge de vérification**, alertes dont **bannière hors-ligne**, navigation, états vides/chargement/erreur, toasts).
- Galerie **Widgetbook** + tests **golden** clair/sombre.
- Lint interdisant couleurs/espacements en dur.
- **Décisions à trancher ici** (voir §5 « Questions ») : police de marque, variante sombre du logo, couleurs d'accent par module, icône d'application (besoin du **fichier vectoriel source**).
- **Dépend de** : rien côté backend ; peut démarrer **dès le début de la Phase 0 [//]**. **Sortie** : galerie consultable, goldens verts dans les deux thèmes.

### L0.10 — App Flutter (shell)

- `mobile/app/` : 3 flavors (dev/staging/prod, ids d'application distincts), bootstrap (DI, Sentry, flags), `ModuleRegistry` (vide de modules métier, prêt à en accueillir), `NavigationPolicy` avec 5 emplacements et défaut Marketplace/Services/Business (masqués tant qu'aucun module n'est enregistré → seuls Accueil/Plus visibles en Phase 0), accueil squelette (cartes vides), i18n fr/en (ARB), client API généré depuis l'OpenAPI du kernel+auth+rbac.
- Parcours : onboarding → OTP → profil → création d'entreprise → invitation.
- Sécurité mobile de base : stockage sécurisé (Keychain/Keystore), obfuscation de build release.
- **Dépend de** : L0.6, L0.7, L0.9. **Sortie** : le parcours S1 partiel (jusqu'à « entreprise créée ») fonctionne sur émulateur **et appareil réel**, avec le thème/logo THY.

### L0.11 — Admin (shell)

- `admin/` : React + Vite + TS, SSO OIDC + MFA staff, RBAC plateforme, sections **Users**, **Audit**, **System settings** (flags, plans/entitlements de base).
- Tokens de design partagés (§L0.9).
- **Dépend de** : L0.6, L0.7, L0.9. **Sortie** : un membre du staff se connecte (MFA), recherche un utilisateur, consulte l'audit.

### L0.12 — Documentation

- `docs/ARCHITECTURE.md`, `DATABASE.md` (généré depuis le catalogue PG + commentaires), `API.md` (lien OpenAPI), `SECURITY.md`, `DEPLOYMENT.md`, `TESTING.md`, `CONTRIBUTING.md`, `CHANGELOG.md` (amorcé par Conventional Commits).
- `docs/adr/` : transcription des décisions D1–D17 validées en ADR numérotées formelles.
- `docs/threat-models/` : premiers threat models (auth, rbac, tenancy).
- **Dépend de** : tous les lots précédents livrés. **Sortie** : documentation à jour, pas de dérive avec le code.

---

## 4. Séquencement

```
Sem. 1     L0.0 → L0.1 → L0.2 → L0.3
Sem. 2–3   L0.5 (+ spike S1 J1–J2)         [//] L0.4 (IaC staging)   [//] L0.9 (design tokens, démarre tôt)
Sem. 4–5   L0.6 (identité)                                            [//] L0.9 (composants, galerie)
Sem. 6     L0.7 (tenancy/RBAC) + tests de fuite
Sem. 7     L0.8 (subscriptions/notifications/media)
Sem. 7–8   L0.10 (shell mobile)            [//] L0.11 (shell admin)
Sem. 8–9   Déploiement staging bout en bout, durcissement, S3 (délivrabilité SMS) conclu
Sem. 9–10  L0.12 (documentation), revue de sortie de phase
```

≈ 8–10 semaines à effectif de référence (H5) ; se resserre à ≈ 6–7 semaines si L0.4/L0.9 sont vraiment menés en parallèle par une deuxième personne dès le départ.

## 5. Spikes et décisions à trancher pendant la Phase 0

| #   | Sujet                                         | Quand                                                                  | Sortie attendue                                  |
| --- | --------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------ |
| S1  | Drizzle + PostGIS + RLS (ADR-003)             | Début L0.5 (2 j)                                                       | Aller / repli Kysely                             |
| S2  | Prototype sync Drift ↔ API (ADR-007)          | Fin de Phase 0 / début Phase 1 (hors périmètre strict L0, préparé ici) | Confirme l'architecture offline avant la Phase 1 |
| S3  | Délivrabilité OTP sur réseaux locaux          | Continu dès L0.6                                                       | Choix définitif des 2 fournisseurs SMS           |
| S4  | Base de performance sur appareil bas de gamme | Dès L0.10                                                              | Mesures de référence (démarrage, mémoire)        |
| S5  | Diligence PSP (non-code)                      | Continu, en parallèle                                                  | Prestataire retenu avant fin Phase 1             |

## 6. Critères de sortie de la Phase 0 (Definition of Done)

- [ ] Parcours **OTP → création d'entreprise → invitation d'un membre avec rôle** fonctionnel en **staging**, sur appareil réel.
- [ ] **Tests de fuite tenant** (RLS + FK composites) verts et **bloquants en CI**.
- [ ] CI complète verte (lint, types, tests, intégration, contrat, sécurité) sur les 3 piles (backend, mobile, admin).
- [ ] Déploiement staging automatisé (image taguée SHA, `migrate` avant `api`/`worker`), environnement `production` protégé et prêt (vide).
- [ ] Observabilité active : erreurs (Sentry), traces/métriques (OTel), logs sans PII, `/health` surveillé, alertes de base.
- [ ] Design system : galerie Widgetbook publiée, goldens clair/sombre verts, tokens conformes à la charte THY.
- [ ] Admin : connexion staff MFA, section Users + Audit opérationnelles.
- [ ] Aucun secret dans le dépôt (`gitleaks` vert) ; aucune donnée fictive activable en production (garde technique testée).
- [ ] Documentation (§L0.12) et ADR à jour et cohérents avec le code livré.

## 7. Risques spécifiques à cette phase

Sur-ingénierie du kernel (R20) → limiter au strict nécessaire pour L0.6–L0.8, ne rien construire « au cas où ». Délivrabilité SMS (R7) → démarrer S3 dès que possible, c'est sur le chemin critique de L0.6. Dérive du design system (dépendance au fichier vectoriel manquant, §8) → ne pas bloquer L0.9 dessus, avancer avec le PNG et substituer dès réception.

---

## 8. Décisions — état

| #   | Sujet                               | Statut                                                                                                                                                                                                                                                                                                                                    |
| --- | ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Cloud                               | **Résolu : GCP** (ADR-012 mis à jour)                                                                                                                                                                                                                                                                                                     |
| 2   | Fichier vectoriel du logo           | **Résolu : indisponible.** On avance avec le PNG ; monogramme carré 1024×1024 déjà extrait ([docs/brand/assets/monogram-icon-source-1024.png](../brand/assets/monogram-icon-source-1024.png)), suffisant pour générer les icônes d'app. Version fond sombre et icône monochrome restent une tâche du designer du logo (non substituable). |
| 3   | Police de marque                    | **Ouvert.** Hypothèse retenue par défaut : géométrique type Montserrat. Je démarre L0.9 avec cette hypothèse, remplaçable sans casser les tokens (la police est un paramètre, pas une couleur).                                                                                                                                           |
| 4   | Dépôt distant / organisation GitHub | **Résolu.** `git@github.com:yombounot-alt/thyEcosystem.git`, branche `main` poussée.                                                                                                                                                                                                                                                      |

Prérequis d'outillage (§2) : **`pnpm` installé** (12.5.1, via npm global — Corepack n'est plus fourni avec Node ≥ 25 sur ce poste). **JDK 17 + Android SDK** restent **non installés** (installation plus lourde, nécessaire avant de builder l'app Android en L0.10, à faire par toi ou sur confirmation explicite).
