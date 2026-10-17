# Tests

Stratégie cible : [blueprint 10](blueprint/10-testing.md), avec sa Definition of Done. Ce document
décrit **ce qui tourne aujourd'hui** et comment le lancer.

## Règle

Une fonctionnalité n'est « terminée » que si des tests prouvent son comportement réel : au
backend, par l'API, contre une vraie base ; dans l'app, par l'écran. Un test qui passe sans
vérifier l'effet (ligne écrite, droit refusé, ligne d'audit) n'en est pas un.

## Backend (`backend/`)

| Suite                 | Commande                                           | Ce qu'elle couvre                                                               |
| --------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------- |
| Unitaires             | `pnpm --filter @thy/backend test`                  | `src/**/*.spec.ts` : logique pure (TOTP, backoff, filtrage Sentry, config…)     |
| End-to-end            | `pnpm --filter @thy/backend run test:e2e`          | `test/**/*.e2e-spec.ts` : application NestJS complète + PostgreSQL + Redis + S3 |
| Contrat OpenAPI       | CI : `openapi:export` puis `git diff --exit-code`  | Le contrat versionné correspond au code                                         |
| Documentation de base | `pnpm --filter @thy/backend run db:doc -- --check` | `docs/DATABASE.md` correspond aux migrations                                    |

### Lancer les e2e en local

```bash
# 1. Pile de développement (PowerShell) : PostgreSQL 5435, Redis 6381, S3 9002, Mailpit, OTel
./infra/scripts/dev-up.ps1
# 2. Compiler puis appliquer les migrations : la suite e2e ne les applique PAS elle-même
cd backend && npx nest build && node --env-file=.env dist/database/migrate-cli.js
# 3. Lancer
pnpm run test:e2e
```

Points à connaître :

- `test/setup-env.ts` charge `backend/.env`. Il désactive la limitation de débit (la suite `auth` la
  réactive pour la tester) et le relais d'outbox (les tests le pilotent par `drainOutbox`).
- Les fichiers partagent une base et s'exécutent l'un après l'autre. Chaque test crée ses propres
  comptes et entreprises (`uniquePhone()`, `createBusiness()` dans `test/harness.ts`) : aucun
  nettoyage n'est nécessaire.
- Suites qui protègent les invariants de sécurité :
  - `kernel/rls.e2e-spec.ts` : RLS forcée sur toute table de tout schéma (sauf les tables globales listées), aucune ligne sans contexte, aucune fuite entre
    entreprises ;
  - `kernel/rbac.e2e-spec.ts` : droits par rôle ;
  - `kernel/auth.e2e-spec.ts` : OTP, rotation et réutilisation des jetons, limitation de débit ;
  - `kernel/admin.e2e-spec.ts` : TOTP, CSRF, verrouillage, matrice des droits, étanchéité entre
    clients et staff ;
  - `business/schema-drift.e2e-spec.ts` : le schéma Prisma correspond à la base créée par les
    migrations.

## Console d'administration (`admin/`)

`pnpm --dir admin test` : Vitest + jsdom + Testing Library. Un faux serveur (`src/test/fake-api.ts`)
refuse toute requête non prévue. Les tests couvrent le client HTTP (CSRF, erreurs), le portail
de connexion (mot de passe, TOTP, session expirée), le filtrage par rôle et les actions à motif.
La sécurité réelle est testée côté backend : les tests du front vérifient l'expérience, pas les
droits.

## Application mobile (`mobile/`)

```bash
cd mobile/app && flutter test                         # app
cd mobile/packages/thy_core && flutter test           # idem pour thy_design_system
dart format --output=none --set-exit-if-changed . ../packages && flutter analyze
```

- `test/api_contract_test.dart` : chaque appel de l'app existe dans `docs/api/openapi.json`.
- Un test vérifie qu'aucune couleur n'est écrite en dur hors des tokens.
- `node shared/design-tokens/build.mjs --check --report` : les fichiers générés sont à jour et les
  40 paires de contraste respectent WCAG.

## CI

| Workflow         | Jobs                                                                                                                                                                        |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci-backend.yml` | Format + lint + typecheck (tout le monorepo via Turbo) ; tests unitaires ; e2e sur PostgreSQL/Redis/RustFS éphémères avec contrôles OpenAPI et `DATABASE.md` ; image Docker |
| `ci-admin.yml`   | Lint, typecheck, tests, build de production de `admin/`                                                                                                                     |
| `ci-mobile.yml`  | Tokens, format, analyse, tests, build web ; build Android (`dev` + `prod` release obfusquée)                                                                                |
| `ci-infra.yml`   | `terraform fmt` + `validate`                                                                                                                                                |
| `security.yml`   | gitleaks, `pnpm audit --audit-level=high`, CodeQL, Trivy + SBOM                                                                                                             |

En cas d'échec, `.github/scripts/run-annotated.sh` publie la fin du journal de l'étape en
annotation. Elle est lisible sans jeton via l'API publique
`/repos/{owner}/{repo}/check-runs/{id}/annotations`.

## Ce qui n'est pas testé

- Aucun test contre les vrais services GCP (Cloud SQL, Cloud Storage) : rien n'est déployé.
- Aucun fournisseur SMS ni push réel.
- Pas de tests de charge, ni de tests de bout en bout sur appareil réel.
