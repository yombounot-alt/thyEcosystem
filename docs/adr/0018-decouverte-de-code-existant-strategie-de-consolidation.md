# ADR-018 — Découverte de code existant : stratégie de consolidation (2026-09-22)

- **Statut** : Acceptée (2026-09-22, précisée le 2026-09-23)

**Contexte.** Avant le premier commit de code applicatif, l'audit de Phase 0 a révélé trois projets existants sur le même poste, hors du dépôt `thyEcosystem` : **`thyBusiness`** (MVP complet et testé, NestJS+Prisma+Flutter), **`thyAcademy`** (backend substantiel, NestJS+TypeORM), **`thyServices`** (backend substantiel, NestJS+SQL brut). Détail de l'audit : `docs/plans/consolidation-strategy.md`. Aucun n'a de vraie donnée de production — seulement des jeux de démo/seed — ce qui change la nature du travail : **portage de code, pas migration de données.**

**Décision (validée par l'utilisateur) :**

1. **ORM : garder la technologie de chaque module** (Prisma pour Business, TypeORM pour Academy, SQL brut pour Services), plutôt que de tout réécrire vers Drizzle (ADR-003 reste la référence pour un **nouveau** module qui n'aurait pas de choix existant, mais ne s'applique plus rétroactivement aux trois modules ci-dessus).
2. **Identité : construire le module central neuf** selon ADR-010/[04-identity-access.md](../blueprint/04-identity-access.md), puis **porter** le code métier des trois modules pour qu'il consomme cette identité centrale au lieu de sa propre table `users`/`auth`.

**Conséquence technique clé** (mécanisme détaillé en [consolidation-strategy.md](../plans/consolidation-strategy.md)) : les tables `core.*` (identité, tenancy, RBAC) sont **possédées par le kernel**, migrées en SQL brut comme n'importe quelle table du kernel — **aucun module métier ne les gère par son propre ORM**. Chaque module lit ces tables via des requêtes/vues en lecture, jamais via une migration de son propre schéma. C'est ce qui rend « un ORM par module » et « une seule identité » compatibles.

**Précisions issues du premier portage (thyBusiness, 2026-09-23).** (a) Les migrations de **tous** les schémas (`core`, `biz`, et ceux des modules à venir) restent des fichiers SQL revus à la main, appliqués par le migrateur du kernel : un ORM n'est qu'un **client de requêtes** et ne crée jamais de schéma (pas de `prisma migrate`) ; un test de non-dérive le garantit. (b) Chaque table métier porte `business_id` avec RLS forcée et clés étrangères composites `(business_id, id)` ; l'ORM n'accède aux données que dans une transaction qui pose `app.business_id`.

**Remise en cause si** : le nombre de modules portés dépasse 3–4 et la fragmentation des outils de migration/tests devient elle-même un risque opérationnel documenté (alors reconsidérer une convergence progressive, module par module, jamais en bloc).

## Mise en œuvre (constat du 2026-10-17)

- thyBusiness porté (schéma `biz`, client Prisma) ; thyAcademy et thyServices restent à porter.
