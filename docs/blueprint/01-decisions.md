# 01 — Registre des décisions d'architecture (proposées)

> Conformément à la consigne : _avant toute décision majeure non définie, expliquer les options, avantages, inconvénients et recommander._
> Statut de toutes les ADR ci-dessous : **Proposé**. Après validation, chacune devient un fichier `docs/adr/NNNN-titre.md` (Phase 0).

Format : Contexte → Options → **Recommandation** → Conséquences → Critère de remise en cause.

---

## ADR-001 — Style d'architecture backend

**Contexte.** 10 modules, une équipe de ~8 personnes, transactions inter-modules fréquentes (commande + stock + paiement + livraison), budget d'exploitation limité, besoin d'évoluer plusieurs années.

| Option                                                                     | Avantages                                                                                                                    | Inconvénients                                                                                                                                                            |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **A. Monolithe modulaire** (un dépôt, un déploiement, frontières strictes) | Transactions ACID simples ; 1 pipeline CI/CD ; refactoring peu coûteux ; ops légères ; extraction possible module par module | Discipline de frontières à outiller ; un bug de perf peut affecter tout le processus (atténué par le processus `worker` séparé)                                          |
| B. Microservices dès le départ                                             | Scalabilité indépendante ; autonomie d'équipes                                                                               | Sagas partout, observabilité distribuée, coût ops énorme, latence réseau, cohérence éventuelle sur des invariants critiques (stock, argent). Prématuré pour 8 personnes. |
| C. Serverless (fonctions)                                                  | Coût à zéro au repos                                                                                                         | Connexions DB, latence de démarrage, WebSocket difficile, débogage/test locaux pénibles, RLS + pooling compliqués                                                        |

**Recommandation : A**, avec **3 points d'entrée du même code** : `api` (HTTP + WS), `worker` (files, outbox, planificateur), `migrate` (job de migration). Un module lourd (IA, tracking de livraison) peut être déployé en `worker` dédié sans réécriture.

**Conséquences.** Règles de dépendances vérifiées en CI ([02-architecture.md](02-architecture.md) §5). Chaque module expose une `facade` ; schéma PG dédié par module.
**Remise en cause si** : un module dépasse durablement 30 % de la charge CPU/DB ou nécessite un cycle de déploiement indépendant → l'extraire (la facade devient une API réseau).

---

## ADR-002 — Organisation du dépôt

| Option                                                                   | Avantages                                                                                   | Inconvénients                                                                                  |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **A. Monorepo** (backend TS + admin TS + mobile Dart + contrats + infra) | Contrats/OpenAPI/tokens partagés ; PR atomiques cross-stack ; une CI ; docs au même endroit | CI à optimiser (cache, `paths` filters) ; deux écosystèmes (pnpm + Melos)                      |
| B. Multi-repos                                                           | Isolation des droits/CI                                                                     | Dérive des contrats, PR coordonnées, versions désynchronisées — coûteux pour une petite équipe |

**Recommandation : A.** Outils : **pnpm workspaces + Turborepo** (backend, admin, `shared/*`), **Melos** (packages Flutter). Le dossier racine `mobile/` est un workspace Melos autonome.
**Remise en cause si** : la CI dépasse 15 min malgré le cache, ou si des équipes externes doivent avoir un accès partiel.

---

## ADR-003 — Accès aux données et migrations

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

---

## ADR-004 — Isolation multi-tenant

| Option                                                              | Avantages                                                                                                                                                   | Inconvénients                                                                    |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| **A. Schéma partagé + `business_id` + RLS** (défense en profondeur) | Un seul schéma à migrer ; coûts minimaux ; requêtes cross-tenant possibles pour l'admin/analytics ; passe à l'échelle (partitionnement par tenant possible) | Une erreur de politique = fuite ; exige tests systématiques                      |
| B. Un schéma PG par tenant                                          | Isolation forte, restauration par tenant                                                                                                                    | Milliers de schémas = migrations ingérables, catalogue PG gonflé, pool difficile |
| C. Une base par tenant                                              | Isolation maximale                                                                                                                                          | Coût et ops prohibitifs pour des petits commerces                                |

**Recommandation : A, à quatre couches** : (1) `TenantGuard` (membership vérifié en base, jamais l'ID envoyé), (2) permissions RBAC, (3) **RLS PostgreSQL** `FORCE` avec rôle applicatif `NOBYPASSRLS`, (4) **FK composites `(business_id, id)`** + tests de fuite automatisés qui échouent si une table tenant n'a pas sa politique.
Deux autres contextes RLS : `app.user_id` (données privées utilisateur : Money, IA) et `app.staff_id` (accès admin audité).
**Remise en cause si** : un client exige un hébergement dédié (→ base par tenant pour ce client seulement, la couche applicative ne change pas).

---

## ADR-005 — Événements et tâches asynchrones

| Option                                               | Avantages                                                                                              | Inconvénients                                                                                      |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| A. `EventEmitter` en mémoire seul                    | Trivial                                                                                                | Perte d'événements au crash ; non durable ; aucun rejeu                                            |
| **B. Outbox transactionnelle (PG) + BullMQ (Redis)** | Pas de double-écriture ; durable ; retries/backoff/DLQ ; simple à opérer ; port `EventBus` remplaçable | Redis devient critique (config `noeviction` + AOF) ; ordre strict non garanti hors partitionnement |
| C. Outbox + Kafka/RabbitMQ/NATS                      | Débit énorme, rétention/rejeu natifs                                                                   | Complexité d'exploitation disproportionnée à ce stade                                              |
| D. Queue Postgres (pg-boss / Graphile Worker)        | Enfilage dans la même transaction, pas de Redis pour les jobs                                          | Charge supplémentaire sur PG ; écosystème d'ordonnancement moindre                                 |

**Recommandation : B.** Règle de cohérence : **mêmes invariants ⇒ même transaction** (ex. décrémenter le stock _dans_ la transaction de vente) ; **effets inter-modules ⇒ événements** (stats, notifications, recherche, livraison). Consommateurs **idempotents** via table `ops.processed_events`.
**Remise en cause si** : > ~2 000 événements/s soutenus ou besoin de rejeu massif → basculer le relais vers NATS JetStream/Kafka (le port ne change pas).

---

## ADR-006 — Architecture et état côté Flutter

| Option                                            | Avantages                                                                        | Inconvénients                                    |
| ------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Riverpod + go_router**, feature-first, packages | Testabilité, injection explicite, peu de boilerplate, très adapté à l'asynchrone | Concepts à apprendre (providers, scoping)        |
| Bloc/Cubit                                        | Très structuré, traçable, standard entreprise                                    | Plus de code ; verbeux pour des écrans simples   |
| Provider seul                                     | Simple                                                                           | Insuffisant à cette échelle                      |
| GetX                                              | Rapide au début                                                                  | Couplage fort, testabilité faible, dette assurée |

**Recommandation : Riverpod** (+ génération de code, `freezed`, `go_router` avec `StatefulShellRoute`). **Architecture en packages Melos** : un package par module + `thy_core`, `thy_design_system`, `thy_api`, `thy_sync`, `thy_l10n`, `thy_engines`. Un module est enregistré dans un `ModuleRegistry` : ajouter un module ne modifie pas le shell.
**Remise en cause si** : l'équipe maîtrise déjà Bloc et n'a pas d'expérience Riverpod → Bloc acceptable, l'architecture en packages ne change pas.

---

## ADR-007 — Base locale mobile et synchronisation offline

**Base locale**

| Option                     | Avantages                                                                                           | Inconvénients                                                               |
| -------------------------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **Drift (SQLite)**         | Relationnel (ventes, stock, contacts), migrations, requêtes typées, SQLCipher possible, très stable | Génération de code                                                          |
| Isar                       | API simple                                                                                          | Incertitude de maintenance ; modèle non relationnel                         |
| Hive / ObjectBox / sqflite | Simplicité / performance / bas niveau                                                               | Non relationnel (Hive), licence/écosystème (ObjectBox), verbosité (sqflite) |

**Synchronisation**

| Option                                                   | Avantages                                                                                   | Inconvénients                                                                         |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **A. Journal de commandes maison + delta-pull**          | Sémantique métier (une vente est un fait) ; contrôle total des conflits ; pas de dépendance | À écrire et tester rigoureusement                                                     |
| B. PowerSync / ElectricSQL (sync d'état Postgres↔SQLite) | Accélère la **lecture** (catalogue, contacts) ; moins de code de pull                       | Ne résout pas la sémantique d'écriture ; dépendance produit ; opérations à comprendre |
| C. Firebase Firestore offline                            | Rapide à prototyper                                                                         | Verrouillage, modèle non relationnel, coûts, multi-tenant/RLS impossibles             |
| D. CRDT (Automerge/Yjs)                                  | Fusion automatique                                                                          | Inadapté aux invariants comptables (stock, argent)                                    |

**Recommandation : Drift chiffré + A pour l'écriture** ; **spike d'une semaine en début de Phase 1** pour décider si B remplace _seulement le pull_ (lecture). Détails : [08-offline-sync.md](08-offline-sync.md).
**Remise en cause si** : le spike montre un gain > 3 semaines de B sur le pull sans compromis de sécurité multi-tenant.

---

## ADR-008 — Moteur de recherche

| Option                                                                          | Avantages                                                                                                                | Inconvénients                                                      |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| **A. PostgreSQL FTS + `pg_trgm` + PostGIS** (derrière un port `SearchProvider`) | Zéro composant en plus ; données cohérentes ; géo natif ; suffisant pour des dizaines/centaines de milliers de documents | Tolérance aux fautes/facettes moins riches ; réglages FR à soigner |
| B. Meilisearch / Typesense                                                      | Typos, facettes, relevance prête à l'emploi, simple à opérer                                                             | Nouveau composant ; synchronisation à maintenir                    |
| C. OpenSearch/Elasticsearch                                                     | Très puissant                                                                                                            | Lourd, coûteux à exploiter                                         |

**Recommandation : A** pour les phases 3 à 8, avec **table dénormalisée `search.documents` alimentée par événements** (recherche globale) et requêtes spécialisées par module (filtres riches). Migration vers B quand : > ~1 M documents, latence p95 > 300 ms, ou besoin de facettes avancées.

---

## ADR-009 — Temps réel

| Option                                               | Avantages                                                                       | Inconvénients                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| **A. Socket.IO (NestJS Gateway) + adaptateur Redis** | Reconnexion, heartbeats, rooms, accusés natifs — précieux sur réseaux instables | Protocole propriétaire au-dessus de WS                         |
| B. WebSocket natif (`ws`)                            | Léger, standard                                                                 | Reconnexion/rooms/ack à écrire                                 |
| C. SSE                                               | Simple, unidirectionnel, traverse bien les proxys                               | Pas de bidirectionnel                                          |
| D. Firebase RTDB/Firestore                           | Rapide                                                                          | Second système de vérité, verrouillage, autorisation dupliquée |

**Recommandation : A.** Le temps réel n'est qu'une **optimisation** : toute information essentielle reste récupérable par REST et par push FCM. SSE utilisé pour le streaming des réponses IA.

---

## ADR-010 — Authentification : construire ou acheter

| Option                                                                   | Avantages                                                                           | Inconvénients                                                            |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **A. Construire dans NestJS** (bibliothèques éprouvées : `jose`, Argon2) | OTP téléphone natif, contexte multi-tenant sur mesure, aucun verrouillage, coût nul | Sécurité à tester avec rigueur                                           |
| B. Keycloak / Ory                                                        | Riche (SSO, MFA)                                                                    | Lourd ; OTP téléphone via extensions ; modèle multi-tenant à adapter     |
| C. Auth0 / Clerk                                                         | Rapide                                                                              | Coût par MAU, dépendance, résidence des données, SMS OTP régional limité |
| D. Firebase Auth                                                         | Intégré à FCM                                                                       | Coût SMS, contrôle limité, fiabilité SMS locale incertaine               |

**Recommandation : A** pour les **comptes clients** ; **OIDC/SSO (ex. Google Workspace) + MFA obligatoire pour le staff** (comptes séparés). Jetons : **access JWT courts, signés asymétriquement (ES256 ou EdDSA, JWKS avec rotation)** ; **refresh tokens opaques, rotation + détection de réutilisation**, stockés hachés. Spécification : [04-identity-access.md](04-identity-access.md).

---

## ADR-011 — Paiements : abstraction, grand livre, absence de custody

| Option                                                                                                                  | Avantages                                                                                                                             | Inconvénients                                                                             |
| ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| A. Intégration directe par fonctionnalité                                                                               | Rapide                                                                                                                                | Dépendance à un prestataire, doublons, impossible à auditer                               |
| **B. `PaymentProvider` abstrait + machine d'états interne + grand livre à double entrée ; THY ne détient pas de fonds** | Multi-fournisseurs, audit complet, réconciliation, remboursements propres ; pas de statut d'établissement de paiement requis a priori | Plus de conception initiale ; dépend des capacités (split/escrow) du fournisseur          |
| C. Portefeuille THY custodial                                                                                           | Contrôle total des flux                                                                                                               | **Réglementation monnaie électronique / établissement de paiement** ; risque légal majeur |

**Recommandation : B.** Le grand livre enregistre des **obligations** (dû au vendeur, commission THY), pas une garde de fonds. Le séquestre éventuel (Marketplace/Services/Agro) passe par les fonctions du PSP agréé — **à valider juridiquement**. Détails : [06-platform-engines.md](06-platform-engines.md) §1.
**Point d'attention.** Les règles des stores (Apple/Google) sur les **biens numériques** (abonnements, cours Academy) peuvent imposer leur facturation intégrée — **à vérifier avant la Phase 10** (risque R9).

---

## ADR-012 — Hébergement, cloud et région

| Option                                                                                  | Avantages                                                                                         | Inconvénients                                                                |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| **A. Conteneurs managés (AWS ECS Fargate ou GCP Cloud Run) + PostgreSQL/Redis managés** | Ops légères, PITR, scaling, services natifs (stockage objet, secret manager, logs) ; IaC portable | Coût > VPS ; verrouillage modéré (atténué par Docker, PG, API compatible S3) |
| B. Kubernetes managé                                                                    | Puissance, portabilité                                                                            | Surdimensionné pour 8 personnes en Phase 0–3                                 |
| C. PaaS (Render/Railway/Fly)                                                            | Très rapide                                                                                       | PostGIS/PITR/région/conformité variables ; coûts à l'échelle                 |
| D. Hébergeurs UE économiques (Scaleway/OVH/Hetzner)                                     | Coût minimal                                                                                      | Plus d'exploitation manuelle ; services managés moins riches                 |

**Décision validée (2026-09-22) : A — GCP.** Services retenus : **Cloud Run** (`api`, `worker`, job `migrate`), **Cloud SQL for PostgreSQL** (extension PostGIS supportée nativement), **Memorystore for Redis** (mode `noeviction` pour les files BullMQ), **Cloud Storage** (accès objet — le port `ObjectStorage` du kernel utilise l'API d'interopérabilité compatible S3 de GCS, donc aucun changement d'adaptateur si on migre plus tard), **Secret Manager**, **Cloud CDN + Cloud Armor** (WAF), **Artifact Registry** (images), **Cloud Logging/Monitoring** en base avant bascule vers la stack Grafana ([ADR-017](#adr-017--observabilité)).
Région : **à mesurer** (§ décision restante) — candidates `europe-west1` (Belgique) ou `europe-west4` (Pays-Bas) sous réserve de latence réelle depuis les réseaux mobiles ouest-africains ; pas de région GCP en Afrique de l'Ouest à ce jour. **IaC (OpenTofu/Terraform, provider `google`)** dès le staging (L0.4). Rester portable : Docker, PostgreSQL standard, API compatible S3, aucun service propriétaire structurant au niveau applicatif.
**Reste à trancher** : budget mensuel cible (dimensionne les instances Cloud SQL/Memorystore et les seuils d'alerte de coût).

---

## ADR-013 — LLM : fournisseur et orchestration

| Option                                                                                   | Avantages                                                                                         | Inconvénients                                               |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| A. Un seul fournisseur en dur                                                            | Simple                                                                                            | Verrouillage, panne = IA indisponible                       |
| **B. Port `LlmProvider` (chat, stream, vision, embeddings) + routage par tâche + repli** | Changer de fournisseur = adaptateur ; coûts maîtrisés (petit modèle pour le routage) ; résilience | Un peu plus de conception                                   |
| C. Modèle open-weights auto-hébergé                                                      | Souveraineté, coût marginal à grande échelle                                                      | GPU, ops, qualité FR/vision/tool-calling à prouver          |
| D. Framework d'agents généraliste (LangChain, etc.)                                      | Rapide pour prototyper                                                                            | Abstractions opaques, contrôle d'autorisation fin difficile |

**Recommandation : B**, orchestration **écrite maison et minimale** (pipeline de [07-ai.md](07-ai.md)) — l'autorisation par outil est le cœur du système et ne doit pas être déléguée à un framework. **Choix du fournisseur par évaluation** sur un jeu de tests THY (français, appel d'outils, vision, latence, coût), pas par défaut. Vérifier contractuellement : non-rétention/non-entraînement, résidence, DPA.

---

## ADR-014 — Cartographie et géocodage

| Option                                                       | Avantages                                          | Inconvénients                                            |
| ------------------------------------------------------------ | -------------------------------------------------- | -------------------------------------------------------- |
| Google Maps Platform                                         | Données/géocodage/itinéraires très riches          | Coût à l'usage élevé ; verrouillage                      |
| Mapbox                                                       | Personnalisable                                    | Coût, données locales variables                          |
| **MapLibre (client) + tuiles OSM hébergées + `GeoProvider`** | Coût maîtrisé, tuiles hors-ligne possibles, ouvert | Qualité des données OSM/géocodage variable selon la zone |

**Recommandation : abstraction `GeoProvider`** (tuiles, géocodage, itinéraires) + **MapLibre** ; **comparer en Phase 3** la qualité OSM vs Google sur la Guinée avant de figer. **PostGIS reste indépendant** du fournisseur (recherches par distance, zones). Adresses : **pin GPS + repère textuel** (adressage informel courant).

---

## ADR-015 — Administration web

| Option                                                                                 | Avantages                                                                       | Inconvénients                                         |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **React + Vite + TypeScript + TanStack (Query/Table/Router) + composants accessibles** | Réutilise les types/contrats TS, écosystème riche pour tables/filtres, PWA-free | À assembler (Refine peut accélérer)                   |
| Next.js                                                                                | SSR/SEO                                                                         | Inutile pour un back-office derrière authentification |
| Flutter Web                                                                            | Réutilisation du code mobile                                                    | Poids, tables/formulaires denses moins adaptés        |
| Low-code (Retool…)                                                                     | Très rapide                                                                     | Sécurité/RBAC/audit externalisés, coûts, verrouillage |

**Recommandation : React SPA.** Tokens de design partagés avec Flutter (source unique JSON → Style Dictionary).

---

## ADR-016 — Identifiants et représentation de l'argent

- **Identifiants : UUIDv7** (triable par le temps → meilleure localité d'index ; **générable côté client** pour l'offline). PG 18+ fournit `uuidv7()` ; sinon génération applicative. Codes lisibles distincts (`THY-7K3F9Q`, base32) pour commandes/reçus.
- **Argent : `BIGINT` en unités mineures + `currency CHAR(3)`**, exposant ISO 4217 issu de `core.currencies` (le GNF a 0 décimale). **Jamais de `float`.** Arrondi défini par devise. Chaque ligne monétaire porte sa devise.
- **Quantités** : `NUMERIC(18,3)` (kg, litres, fractions), unité via `core.units`.
- **Temps** : `timestamptz` UTC partout ; fuseau du business pour les frontières de « jour » des rapports.
- **Téléphones** : E.164 normalisé (libphonenumber).

---

## ADR-017 — Observabilité

| Option                                                                                            | Avantages                                | Inconvénients                            |
| ------------------------------------------------------------------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| **Sentry (erreurs/crashs/perf mobile+web+API) + OpenTelemetry → Grafana (Prometheus/Loki/Tempo)** | Standard ouvert, portable, coût maîtrisé | Deux outils à administrer                |
| Datadog / New Relic                                                                               | Tout-en-un                               | Coût élevé à l'échelle                   |
| Natif cloud (CloudWatch/Cloud Logging)                                                            | Intégré, zéro installation               | Corrélation et UX moindres, verrouillage |

**Recommandation : option 1** (versions managées au début). Détails : [12-devops-monitoring.md](12-devops-monitoring.md) §5.

---

## ADR-018 — Découverte de code existant : stratégie de consolidation (2026-09-22)

**Contexte.** Avant le premier commit de code applicatif, l'audit de Phase 0 a révélé trois projets existants sur le même poste, hors du dépôt `thyEcosystem` : **`thyBusiness`** (MVP complet et testé, NestJS+Prisma+Flutter), **`thyAcademy`** (backend substantiel, NestJS+TypeORM), **`thyServices`** (backend substantiel, NestJS+SQL brut). Détail de l'audit : `docs/plans/consolidation-strategy.md`. Aucun n'a de vraie donnée de production — seulement des jeux de démo/seed — ce qui change la nature du travail : **portage de code, pas migration de données.**

**Décision (validée par l'utilisateur) :**

1. **ORM : garder la technologie de chaque module** (Prisma pour Business, TypeORM pour Academy, SQL brut pour Services), plutôt que de tout réécrire vers Drizzle (ADR-003 reste la référence pour un **nouveau** module qui n'aurait pas de choix existant, mais ne s'applique plus rétroactivement aux trois modules ci-dessus).
2. **Identité : construire le module central neuf** selon ADR-010/[04-identity-access.md](04-identity-access.md), puis **porter** le code métier des trois modules pour qu'il consomme cette identité centrale au lieu de sa propre table `users`/`auth`.

**Conséquence technique clé** (mécanisme détaillé en [consolidation-strategy.md](../plans/consolidation-strategy.md)) : les tables `core.*` (identité, tenancy, RBAC) sont **possédées par le kernel**, migrées en SQL brut comme n'importe quelle table du kernel — **aucun module métier ne les gère par son propre ORM**. Chaque module lit ces tables via des requêtes/vues en lecture, jamais via une migration de son propre schéma. C'est ce qui rend « un ORM par module » et « une seule identité » compatibles.

**Précisions issues du premier portage (thyBusiness, 2026-09-23).** (a) Les migrations de **tous** les schémas (`core`, `biz`, et ceux des modules à venir) restent des fichiers SQL revus à la main, appliqués par le migrateur du kernel : un ORM n'est qu'un **client de requêtes** et ne crée jamais de schéma (pas de `prisma migrate`) ; un test de non-dérive le garantit. (b) Chaque table métier porte `business_id` avec RLS forcée et clés étrangères composites `(business_id, id)` ; l'ORM n'accède aux données que dans une transaction qui pose `app.business_id`.

**Remise en cause si** : le nombre de modules portés dépasse 3–4 et la fragmentation des outils de migration/tests devient elle-même un risque opérationnel documenté (alors reconsidérer une convergence progressive, module par module, jamais en bloc).

## Décisions mineures (défauts proposés, modifiables sans débat)

| Sujet                  | Choix par défaut                                                                   | Raison courte                         |
| ---------------------- | ---------------------------------------------------------------------------------- | ------------------------------------- |
| Validation API         | **Zod** (source unique validation + OpenAPI + types) ; repli class-validator       | Un schéma, trois usages               |
| Format d'erreur        | **RFC 9457 `application/problem+json`** + `code` stable i18n                       | Standard, traduisible                 |
| Pagination             | **Curseur (keyset)**, jamais `OFFSET` sur listes chaudes                           | Perf + stabilité                      |
| Logs                   | **pino** JSON, redaction déclarative                                               | Vitesse, sécurité                     |
| Documentation API      | **OpenAPI 3.1** générée du code, snapshot versionné + diff cassant en CI           | Contrat vérifié                       |
| Client API mobile      | **Généré** depuis OpenAPI (Dart/Dio)                                               | Zéro dérive                           |
| Réseau mobile          | **Dio** + intercepteurs (refresh single-flight, idempotency, retry GET)            | Mature                                |
| Modèles Dart           | **freezed + json_serializable**                                                    | Immuabilité                           |
| Lint TS / Dart         | ESLint strict + `dependency-cruiser` / `very_good_analysis`-like                   | Frontières + qualité                  |
| Feature flags          | **Table + cache** maison (Phase 0) ; évaluer GrowthBook/Unleash ensuite            | Minimal d'abord                       |
| Vidéo Academy          | **Plateforme HLS externe** (Cloudflare Stream/Mux/Bunny)                           | Ne pas héberger de streaming soi-même |
| Analytics produit      | Événements serveur (outbox) + **PostHog** (consentement) ; BI interne **Metabase** | Vie privée + coût                     |
| E-mail transactionnel  | Fournisseur SMTP/API interchangeable (`EmailProvider`)                             | Portabilité                           |
| Génération PDF (reçus) | Côté serveur (template HTML → PDF) + reçu texte/partage image côté mobile          | Fiabilité hors-ligne                  |
| Convention commits     | **Conventional Commits** + changelog automatisé                                    | Traçabilité                           |
| Branches               | **Trunk-based**, branches courtes, `main` protégée                                 | Intégration continue                  |
