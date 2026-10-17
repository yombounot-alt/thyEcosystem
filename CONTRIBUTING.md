# Contribuer

## Prérequis

- Node.js ≥ 22.22.1 et pnpm 10 (`corepack enable`)
- Docker Desktop, pour PostgreSQL, Redis, S3 (RustFS), Mailpit et le collecteur OpenTelemetry
- Flutter 3.47, pour l'app mobile
- Terraform ≥ 1.9, seulement pour l'infrastructure

## Premier démarrage

```powershell
pnpm install
./infra/scripts/dev-up.ps1                     # pile locale (ports décalés : PostgreSQL 5435, Redis 6381, S3 9002)
cd backend
cp .env.example .env                           # valeurs de développement
npx nest build
node --env-file=.env --import ./dist/instrumentation.js dist/main.js   # API sur http://localhost:3300
```

En développement, l'API applique les migrations en attente à son démarrage, car `.env` fournit
`MIGRATOR_DATABASE_URL`. Un environnement déployé ne lui donne pas cette variable. `pnpm start:dev` (rechargement à chaud)
ne charge **pas** `backend/.env` : exporter les variables avant de l'utiliser.

- **Console d'administration** : créer un compte ([runbook](docs/runbooks/staff-accounts.md)),
  puis `pnpm --dir admin dev` et ouvrir <http://localhost:5174>. Le serveur de développement relaie
  `/admin/v1` vers l'API (port 3300).
- **App mobile** : `cd mobile/app && flutter run --flavor dev`. En `dev`, l'app vise
  `http://10.0.2.2:3300/api/v1` (l'hôte vu depuis l'émulateur Android). Sur un autre appareil :
  `--dart-define=THY_API_BASE_URL=http://<ip-du-poste>:3300/api/v1`. En développement, le code
  OTP est écrit dans les journaux de l'API.

## Règles du projet

Elles ne se négocient pas dans une PR :

1. **Le serveur est la seule source de vérité.** Aucun droit ne s'appuie sur le client.
2. **Aucun paiement simulé** ni donnée fictive activable en production.
3. **Toute table métier** porte `business_id` et la RLS forcée
   ([runbook migrations](docs/runbooks/migrations.md)).
4. **Aucun secret, jeton ni donnée personnelle** dans le code, les journaux, les tests ou une PR.
5. **« Terminé » veut dire testé** : tests e2e contre une vraie base pour le backend
   ([TESTING.md](docs/TESTING.md)).
6. **Une décision d'architecture nouvelle passe par une ADR** ([docs/adr/](docs/adr/README.md)) :
   options, recommandation, validation, puis code.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/fr/), vérifiés par commitlint dans le
hook `commit-msg` : `type(portée): sujet en minuscules`. Types : `feat`, `fix`, `docs`, `ci`,
`refactor`, `perf`, `build`, `test`, `chore`. Exemple :
`fix(auth): refuse a reused refresh token`.

Le hook `pre-commit` (lint-staged) vérifie le format Prettier des fichiers modifiés. Le changelog se
reconstruit depuis ces messages : `node tools/changelog.mjs`.

## Avant de pousser

```bash
pnpm format:check && pnpm lint && pnpm typecheck && pnpm test
pnpm --filter @thy/backend run test:e2e        # pile locale démarrée, migrations appliquées
```

Selon ce qui a changé :

| Changement                         | À faire aussi                                                                       |
| ---------------------------------- | ----------------------------------------------------------------------------------- |
| Route ou DTO de l'API publique     | `pnpm --filter @thy/backend run openapi:export` et commiter `docs/api/openapi.json` |
| Migration                          | `pnpm --filter @thy/backend run db:doc` et commiter `docs/DATABASE.md`              |
| `shared/design-tokens/tokens.json` | `pnpm --filter @thy/design-tokens generate` (Dart requis)                           |
| App mobile                         | `dart format`, `flutter analyze`, `flutter test` dans `mobile/app`                  |

La CI vérifie tout cela et échoue si un fichier généré n'est pas à jour.

## Pièges connus

- Les tests e2e **n'appliquent pas** les migrations : lancer le migrateur avant.
- Le port 3000 est souvent pris par un autre projet ; l'API THY écoute sur 3300.
- Turbo exécute `lint`, `test` et `^build` sur tous les paquets du workspace. Un script qui exige
  Dart ne doit pas s'appeler `build`.
- Une migration déjà appliquée ne se modifie jamais ([runbook](docs/runbooks/migrations.md)).

## Documentation

| Besoin                          | Document                                                                  |
| ------------------------------- | ------------------------------------------------------------------------- |
| Comprendre ce qui existe        | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)                              |
| La cible et la feuille de route | [docs/blueprint/](docs/blueprint/README.md)                               |
| Le plan de la phase en cours    | [docs/plans/phase-0-foundation.md](docs/plans/phase-0-foundation.md)      |
| Pourquoi un choix a été fait    | [docs/adr/](docs/adr/README.md)                                           |
| La base de données              | [docs/DATABASE.md](docs/DATABASE.md) (généré)                             |
| L'API                           | [docs/API.md](docs/API.md)                                                |
| Les tests                       | [docs/TESTING.md](docs/TESTING.md)                                        |
| Le déploiement                  | [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)                                  |
| La sécurité                     | [SECURITY.md](SECURITY.md), [threat models](docs/threat-models/README.md) |
| L'exploitation                  | [docs/runbooks/](docs/runbooks/)                                          |
