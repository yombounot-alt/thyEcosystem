# ADR-003 — Accès aux données et migrations

- **Statut** : Acceptée (2026-09-22), **amendée par [ADR-018](0018-decouverte-de-code-existant-strategie-de-consolidation.md)**

**Besoins** : PostGIS (geography), RLS avec contexte transactionnel, FK composites, schémas PG par module, partitionnement, SQL de migration écrit/relu à la main, typage fort, perf.

| Option                    | Avantages                                                                                                                         | Inconvénients                                                                                                                   |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Prisma                    | Excellente DX, client typé, communauté immense                                                                                    | Types PostGIS via `Unsupported` → SQL brut ; RLS/`SET LOCAL` par transaction moins naturel ; abstraction lourde pour SQL avancé |
| TypeORM                   | Intégration Nest native, mature                                                                                                   | Typage plus faible, requêtes complexes pénibles, dynamique de maintenance discutée                                              |
| **Drizzle ORM**           | Schéma TS proche du SQL, `pgSchema`, colonnes geometry, politiques RLS déclarables, migrations SQL éditables (drizzle-kit), léger | Écosystème plus jeune ; intégration Nest à écrire (provider maison)                                                             |
| Kysely (+ migrations SQL) | Contrôle total, requêtes typées, idéal SQL avancé                                                                                 | Pas de couche schéma/relations ; plus de code à écrire                                                                          |
| MikroORM                  | Unit-of-Work, filtres multi-tenant, DDD                                                                                           | Communauté plus petite, courbe d'apprentissage                                                                                  |

**Recommandation : Drizzle** pour schéma + requêtes, **migrations SQL relues à la main** (RLS, triggers, partitions, extensions écrits en SQL pur). **Spike de 2 jours en Phase 0** avec critères d'acceptation : (1) colonne `geography(Point)` + requête `ST_DWithin` ; (2) `SET LOCAL app.business_id` dans une transaction + politique RLS effective ; (3) FK composites ; (4) schémas multiples ; (5) migration `expand/contract` rejouable. **Repli : Kysely.**
**Remise en cause si** le spike échoue sur (2) ou (3).

## Mise en œuvre (constat du 2026-10-17)

- Drizzle n'a jamais été utilisé et le spike n'a pas eu lieu.
- Le kernel accède aux données en SQL brut avec `pg` (service `Db`, lignes converties en camelCase, `withTenant()`). Le module Business garde le client Prisma (requêtes seulement).
- Migrations : fichiers SQL écrits à la main dans `backend/migrations/`, migrateur maison forward-only avec somme de contrôle et verrou consultatif. Aucun ORM ne crée de schéma.
