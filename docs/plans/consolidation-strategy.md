# Stratégie de consolidation — code existant → thyEcosystem

> Statut : décisions D-ORM et D-Identité validées (2026-09-22). Ce document remplace la partie
> « greenfield » du plan [phase-0-foundation.md](phase-0-foundation.md) pour tout ce qui touche
> Business, Services et Academy : ce ne sont plus des modules à construire, mais des modules
> **existants à porter**.

---

## 1. Ce qui a été trouvé (rappel, détail dans la conversation d'audit)

| Projet          | Chemin                                       | Stack backend                            | Git      | Verdict                                                             |
| --------------- | -------------------------------------------- | ---------------------------------------- | -------- | ------------------------------------------------------------------- |
| **thyBusiness** | `C:\Users\HP\Desktop\vibeCoding\thyBusiness` | NestJS + **Prisma**                      | 1 commit | MVP complet et **testé de bout en bout**, app Flutter incluse       |
| **thyAcademy**  | `C:\Users\HP\Desktop\vibeCoding\thyAcademy`  | NestJS + **TypeORM**                     | aucun    | Backend substantiel (pipeline IA, quiz, quotas), pas d'app branchée |
| **thyServices** | `C:\Users\HP\Desktop\vibeCoding\thyServices` | NestJS + **SQL brut** (migrateur maison) | aucun    | Backend substantiel (matching, litiges, avis), pas d'app branchée   |

**Hors périmètre, ne pas toucher** (décision utilisateur) : `thyAppTransit` (ERP transit/douane, produit séparé), `guineeBesoin`/Nafa (carnet de crédit, produit séparé).

**Fait central qui change tout** : aucun de ces trois projets n'a de vraie donnée de production. Consolider = **porter du code testé vers une nouvelle architecture**, pas migrer des données réelles. Le risque est donc bien plus bas qu'une consolidation classique.

---

## 2. Mécanisme technique : un ORM par module + une seule identité

La difficulté apparente — trois technologies d'accès aux données différentes, mais un seul compte utilisateur exigé par le blueprint — se résout par une règle simple :

> **Les tables `core.*` (identité, entreprises, RBAC, sessions, appareils) appartiennent au kernel, migrées en SQL brut comme toute autre table transverse. Aucun module métier ne les gère avec son propre ORM — il les lit.**

```
                      ┌─────────────────────────────────────────┐
                      │   core.* (kernel, migrations SQL brutes) │
                      │   users · businesses · business_members  │
                      │   sessions · roles · permissions          │
                      └───────────────┬───────────────────────────┘
                                       │ lecture seule (vue / requête directe / procédure)
        ┌──────────────────┬──────────┴──────────┬──────────────────┐
        │                  │                     │                  │
 ┌──────▼──────┐   ┌───────▼───────┐    ┌────────▼────────┐  ┌──────▼──────┐
 │ biz.* (Prisma)│  │ acd.* (TypeORM)│   │ svc.* (SQL brut) │  │ futur module │
 │ thyBusiness   │  │ thyAcademy     │   │ thyServices      │  │ (Drizzle,    │
 │ products,     │  │ courses, quiz, │   │ requests, quotes,│  │  ADR-003)    │
 │ sales, stock… │  │ ai_requests…   │   │ disputes…        │  │              │
 └───────────────┘  └────────────────┘   └──────────────────┘  └──────────────┘
```

### Comment chaque ORM « voit » les tables `core.*`

| ORM                     | Mécanisme                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Prisma** (Business)   | Les modèles `User`, `Business`, `RefreshToken`, `OtpVerification` sont **retirés** de `schema.prisma`. Les besoins de lecture (ex. `businessId` courant, rôle de l'utilisateur) passent par le **kernel d'identité** (service injecté), pas par le client Prisma. Si une jointure SQL brute est vraiment nécessaire, `prisma.$queryRaw` sur `core.businesses` est acceptable en lecture seule (jamais de migration Prisma sur ces tables). |
| **TypeORM** (Academy)   | Les entités `identity.entities.ts` actuelles sont **retirées** du datasource TypeORM (`synchronize` déjà à `false` en pratique via migrations — donc pas de risque que TypeORM tente de gérer `core.*`). Lecture via le service d'identité partagé.                                                                                                                                                                                        |
| **SQL brut** (Services) | Le plus simple des trois : Services interroge déjà tout en SQL paramétré. Ses requêtes touchant `users`/`sessions` deviennent des requêtes vers `core.users`/`core.sessions` au lieu de ses propres tables.                                                                                                                                                                                                                                |

### Ce qui EST partagé malgré tout (indépendant de l'ORM)

- **Le pipeline HTTP du kernel** ([02-architecture.md §5.2](../blueprint/02-architecture.md)) : `AuthGuard`, `TenantGuard`, throttler, idempotence, format d'erreur `problem+json`. Chaque module branche ses contrôleurs derrière ces guards communs au lieu de ses propres `JwtAuthGuard`/`RolesGuard` maison.
- **Le format du JWT** : un seul émetteur, un seul jeu de clés (JWKS), un seul schéma de claims. Les trois modules cessent de signer leurs propres jetons.
- **L'outbox/événements** : un seul mécanisme (`ops.outbox_events`), déjà proche de celui de thyServices (qui a déjà un pattern outbox transactionnel — à **réutiliser comme référence d'implémentation**, il est déjà excellent).
- **L'observabilité, la config, les secrets** : un seul kernel pour les trois.

### Nuance de sécurité à trancher lors de la conception du module identité

thyBusiness lit `businessId` directement depuis un **claim du JWT** (`@CurrentBusiness()`), pas depuis une revérification base à chaque requête. C'est plus simple et plus performant que le design de [04-identity-access.md §5](../blueprint/04-identity-access.md) (revérification en base par requête), au prix d'un changement de rôle/entreprise qui n'est effectif qu'au prochain jeton (15 min). **Décision proposée** : garder l'esprit thyBusiness (claim de contexte dans le JWT, re-signé à chaque changement d'entreprise active) mais **ajouter** une invalidation immédiate pour les cas sensibles (bannissement, retrait d'un membre) via le `token_version`/`sid` déjà prévu — le meilleur des deux. À confirmer en concevant le module `auth` (L0.6 du plan Phase 0).

---

## 3. Plan de portage par module

### Ordre recommandé : **thyBusiness d'abord**

Raisons : c'est le seul des trois avec une **app mobile fonctionnelle bout en bout**, donc le seul qui valide immédiatement toute la chaîne (kernel → identité → module → app). Academy et Services n'ont pas encore d'app : les porter ensuite est moins urgent et bénéficiera d'un kernel déjà éprouvé par Business.

### 3.1 thyBusiness → `backend/modules/business` (+ `mobile/packages/features/business`)

| Étape                                         | Détail                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Copie                                         | `apps/api/src/modules/*` → `backend/modules/business/{api,application,domain,infrastructure}` (réorganisé selon [02-architecture.md §5.1](../blueprint/02-architecture.md)) ; `apps/api/prisma/schema.prisma` → `backend/modules/business/infrastructure/prisma/schema.prisma`, schéma PG renommé `biz`                                                                                                                         |
| **Retiré** du module (déplacé vers le kernel) | `User`, `RefreshToken`, `OtpVerification`, `BusinessMember` (partiellement — la relation membre/rôle devient `core.business_members`), les guards `JwtAuthGuard`/`BusinessContextGuard`/`OwnerGuard` maison → remplacés par les guards kernel                                                                                                                                                                                   |
| **Conservé tel quel** (déjà excellent)        | `SalesService.quote` (calcul serveur du montant), l'idempotence par `clientRequestId`, toute la mécanique `ManualPayment`/`PaymentMethod` (devient la base de [06-platform-engines.md §1](../blueprint/06-platform-engines.md), remplace l'hypothèse « PSP réel en Phase 1 » — voir §4 ci-dessous), le cache offline Dio + file de ventes en attente côté Flutter, `money.ts`, les tests e2e                                    |
| **À adapter**                                 | `Business.currency`/`timezone` restent sur `core.businesses` (déjà prévu côté kernel) ; les relations Prisma vers `User` deviennent des colonnes `user_id` simples (FK logique vers `core.users`, pas de FK Prisma inter-schéma)                                                                                                                                                                                                |
| App mobile                                    | Le code de `apps/mobile/lib/features/*` migre dans `mobile/packages/features/business` ; `apps/mobile/lib/core/*` (api client, theme, storage) fusionne avec `thy_core`/`thy_design_system` du shell déjà créé — **la palette de couleurs et les tokens du nouveau design system THY remplacent `app_theme.dart`** (le logo/la charte donnés aujourd'hui sont la version « officielle », `app_theme.dart` actuel est antérieur) |
| CI                                            | `.github/workflows/ci.yml` de thyBusiness inspire les règles CI de `backend/modules/business` (tests e2e Jest déjà écrits, à rebrancher)                                                                                                                                                                                                                                                                                        |

### 3.2 thyServices → `backend/modules/services`

| Étape                                                           | Détail                                                                                                                                                                                                                                                                                                                                                                               |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Copie                                                           | `backend/src/*` → `backend/modules/services/*`, migrations SQL → schéma `svc`, migrateur maison (`migrate.ts`) **conservé** (il est déjà exactement le style « migrations SQL revues à la main » que le blueprint recommandait pour le kernel)                                                                                                                                       |
| **Retiré**                                                      | `users`, `refresh_tokens`, `otp_codes`, `login_events`, `user_devices` (deviennent `core.*`) ; `auth/` module entier remplacé par les guards kernel                                                                                                                                                                                                                                  |
| **Conservé tel quel** (référence pour le reste de l'écosystème) | Les **12 garde-fous en base** (triggers `guard_profile_verified`, `guard_review_eligibility`…), la contrainte d'exclusion anti-double-réservation, `request-state-machine.ts`, le pattern outbox transactionnel (**à généraliser au kernel**, voir §2), `scoring.ts` (matching), `risk.ts` (détection faux avis)                                                                     |
| **À adapter**                                                   | `professional_profiles.user_id` référence `core.users(id)` (FK applicative, plus FK SQL stricte inter-schéma sauf si les deux schémas restent dans la même base — c'est le cas, donc une vraie FK Postgres inter-schéma **reste possible** ici puisque tout vit dans une seule base ; seule l'inter-ORM empêche la génération automatique, pas la contrainte elle-même)              |
| Note                                                            | Ce module devient la **référence d'implémentation** du moteur `verification` et `moderation` transversal ([06-platform-engines.md §5–6](../blueprint/06-platform-engines.md)) — envisager d'en extraire la partie générique (vérification, litiges) comme moteur partagé plutôt que de la dupliquer pour Immo/Jobs plus tard. **Décision à prendre à ce moment-là**, pas maintenant. |

### 3.3 thyAcademy → `backend/modules/academy`

| Étape                                                                            | Détail                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Copie                                                                            | `backend/src/*` → `backend/modules/academy/*`, entités TypeORM → schéma `acd`                                                                                                                                                                                                                                                                                                    |
| **Retiré**                                                                       | `identity.entities.ts` (users, refresh_tokens) → `core.*` ; `auth/` maison remplacé                                                                                                                                                                                                                                                                                              |
| **Conservé tel quel** (référence directe pour [07-ai.md](../blueprint/07-ai.md)) | Le **pipeline IA entier** (traitement image → OCR → résolution → validation → moteur de certitude déterministe) est plus abouti que ma section blueprint correspondante — **ce document doit être mis à jour pour refléter ce pipeline**, pas l'inverse. Le pattern quota réserver/valider/rembourser devient le modèle pour tous les quotas IA de l'écosystème (ADR à ajouter). |
| **À adapter**                                                                    | `users.country_id`/`education_level_id` : le multi-pays par les données (§6 de leur ARCHITECTURE.md) est une bonne idée générale — évaluer si `core.countries` du kernel doit absorber ce modèle plus riche (pays → niveaux → séries → matières) plutôt que le `core.countries` minimal actuellement prévu                                                                       |

---

## 4. Impact sur le blueprint et la roadmap

| Sujet                                                                             | Avant (blueprint v0.1, greenfield) | Après (avec code existant)                                                                                                                                                                                                                                                                                                                                                                                                         |
| --------------------------------------------------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Paiements Phase 1                                                                 | PSP réel en fin de Phase 1         | **Reprendre le modèle « paiement direct vérifié par le propriétaire » de thyBusiness** comme solution v1 réaliste pour le marché guinéen ; un PSP réel devient une **option future** (comme documenté dans leurs ADR 0010/0011), pas un prérequis de fin de Phase 1                                                                                                                                                                |
| IA (Phase 2 / [07-ai.md](../blueprint/07-ai.md))                                  | Pipeline à concevoir               | **Déjà conçu et partiellement implémenté** par thyAcademy — le document blueprint sera mis à jour pour reprendre le moteur de certitude déterministe telle quelle                                                                                                                                                                                                                                                                  |
| Vérification/Modération (Phase 3, [06 §5-6](../blueprint/06-platform-engines.md)) | Moteur à concevoir                 | thyServices fournit une **implémentation de référence** directement réutilisable pour Services, et à généraliser plus tard                                                                                                                                                                                                                                                                                                         |
| Ordre des phases                                                                  | 0 → 1 (Business) → 2 (IA) → …      | Le portage de Business (3.1) **remplace** l'essentiel de la Phase 1 côté code (il reste : brancher sur l'identité centrale, employés/RBAC multi-membres réels puisque le MVP solo ne les avait pas, abonnements). Services et Academy avancent en parallèle dès que le kernel est stable, **avant** leur tour officiel (Phase 5/10) — à condition de ne pas leur donner d'app mobile avant leur phase, uniquement le backend porté |
| Design system                                                                     | À construire de zéro (L0.9)        | thyBusiness a déjà un `app_theme.dart` fonctionnel (Material, pas encore aligné sur la charte THY d'aujourd'hui) — **remplacé**, pas fusionné, par les tokens de [docs/brand/README.md](../brand/README.md)                                                                                                                                                                                                                        |

---

## 5. Ce qui ne change pas

Tout le reste du blueprint validé reste la cible : un seul dépôt, un seul déploiement (api/worker/migrate), un seul kernel (config/db/events/queue/sécurité/observabilité), une seule identité, un seul RBAC, une seule base PostgreSQL avec schémas par module, un seul design system, la roadmap Phase 0 → 11 dans son ordre (Business, IA, Marketplace, Delivery, Services, Immo, Jobs, Agro, Money, Academy, Intégration) — **Services et Academy gardent leur place dans cet ordre pour leur mise en app/production**, seul leur **backend** avance plus tôt grâce au portage.

---

## 6. Prochaines étapes concrètes

1. **Sécurité d'abord** : `git init` + premier commit dans `thyAcademy` et `thyServices` (aucun des deux n'est versionné actuellement) — pur filet de sécurité avant tout portage, aucun risque.
2. Reprendre le plan [phase-0-foundation.md](phase-0-foundation.md) lots L0.5–L0.8 (kernel, identité, tenancy/RBAC) en les concevant **dès le départ** comme le point d'ancrage des trois modules (claims JWT incluant le contexte entreprise à la thyBusiness, RBAC couvrant les rôles des trois projets : OWNER/ADMIN/MANAGER/CASHIER (Business), CLIENT/PROFESSIONAL/MODERATOR/ADMIN (Services), STUDENT/EDITOR/ADMIN (Academy)).
3. Porter thyBusiness (3.1) dès que L0.5–L0.7 sont stables — c'est le test de bout en bout du kernel.
4. Porter thyServices et thyAcademy en parallèle une fois thyBusiness validé.
5. Mettre à jour [07-ai.md](../blueprint/07-ai.md) et [06-platform-engines.md](../blueprint/06-platform-engines.md) pour refléter les implémentations de référence trouvées (tâche de documentation, pas de code).
