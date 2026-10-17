# ADR-015 — Administration web

- **Statut** : Acceptée (2026-09-22, validation du blueprint)

| Option                                                                                 | Avantages                                                                       | Inconvénients                                         |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **React + Vite + TypeScript + TanStack (Query/Table/Router) + composants accessibles** | Réutilise les types/contrats TS, écosystème riche pour tables/filtres, PWA-free | À assembler (Refine peut accélérer)                   |
| Next.js                                                                                | SSR/SEO                                                                         | Inutile pour un back-office derrière authentification |
| Flutter Web                                                                            | Réutilisation du code mobile                                                    | Poids, tables/formulaires denses moins adaptés        |
| Low-code (Retool…)                                                                     | Très rapide                                                                     | Sécurité/RBAC/audit externalisés, coûts, verrouillage |

**Recommandation : React SPA.** Tokens de design partagés avec Flutter (source unique JSON → Style Dictionary).

## Mise en œuvre (constat du 2026-10-17)

- `admin/` : React 19 + Vite + TanStack Query/Router (lot L0.11). Pas encore de TanStack Table.
- Tokens partagés : générateur maison `shared/design-tokens/build.mjs` (Dart + CSS, contraste WCAG vérifié) au lieu de Style Dictionary.
- Authentification du staff : [ADR-020](0020-authentification-du-staff-comptes-thy-et-totp.md).
