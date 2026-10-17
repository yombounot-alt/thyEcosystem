# ADR-002 — Organisation du dépôt

- **Statut** : Acceptée (2026-09-22, validation du blueprint)

| Option                                                                   | Avantages                                                                                   | Inconvénients                                                                                  |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **A. Monorepo** (backend TS + admin TS + mobile Dart + contrats + infra) | Contrats/OpenAPI/tokens partagés ; PR atomiques cross-stack ; une CI ; docs au même endroit | CI à optimiser (cache, `paths` filters) ; deux écosystèmes (pnpm + Melos)                      |
| B. Multi-repos                                                           | Isolation des droits/CI                                                                     | Dérive des contrats, PR coordonnées, versions désynchronisées — coûteux pour une petite équipe |

**Recommandation : A.** Outils : **pnpm workspaces + Turborepo** (backend, admin, `shared/*`), **Melos** (packages Flutter). Le dossier racine `mobile/` est un workspace Melos autonome.
**Remise en cause si** : la CI dépasse 15 min malgré le cache, ou si des équipes externes doivent avoir un accès partiel.

## Mise en œuvre (constat du 2026-10-17)

- Monorepo : pnpm workspaces + Turborepo (`backend`, `admin`, `shared/*`), Melos pour `mobile/`.
- Piège connu : Turbo exécute `lint`/`test`/`^build` sur tous les paquets du workspace ; un script qui exige Dart ne doit pas s'appeler `build` (voir `shared/design-tokens/package.json`).
