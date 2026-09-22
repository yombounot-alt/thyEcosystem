# THY — Master Technical Blueprint

> **Statut : v0.1 — proposition en attente de validation** · Date : 2026-09-21
> Périmètre : architecture cible + roadmap Phase 0 → Phase 11.
> **Aucun code applicatif n'a été écrit.** Ce dossier est la base de la Phase 0 (Foundation).

---

## 1. THY en une page

THY est **une seule application mobile** (Flutter) adossée à **un seul backend** (NestJS, monolithe modulaire), **une seule base** (PostgreSQL + PostGIS) et **un seul compte utilisateur**. Les dix modules ne sont pas des applications : ce sont des **modules métier** posés sur des **moteurs de plateforme partagés**.

```
┌─────────────────────────────── APPLICATION FLUTTER (une seule) ───────────────────────────────┐
│  Shell (navigation adaptative · accueil personnalisable · recherche globale · assistant IA)   │
│  Business │ Marketplace │ Services │ Delivery │ Immo │ Jobs │ Academy │ Agro │ Money │ AI    │
└──────────────────────────────────────────────┬───────────────────────────────────────────────┘
                                               │ REST /api/v1 + WebSocket (OpenAPI)
┌──────────────────────────────────────────────▼───────────────────────────────────────────────┐
│ MODULES MÉTIER   business · marketplace · services · delivery · immo · jobs · academy · agro  │
│                  finance(Money) · ai                                                          │
├───────────────────────────────────────────────────────────────────────────────────────────────┤
│ MOTEURS DE PLATEFORME (partagés, construits au premier besoin)                                │
│  identité · tenancy/RBAC · abonnements/entitlements · paiements+ledger · notifications        │
│  messagerie · recherche · avis · vérification · modération/signalements · médias · géo        │
│  favoris/alertes · audit · support · flags/config · sync offline · analytics                  │
├───────────────────────────────────────────────────────────────────────────────────────────────┤
│ KERNEL (technique, zéro métier)  config · db/tx/RLS · événements+outbox · files · cache ·     │
│  http pipeline · sécurité · observabilité · stockage objet · i18n                             │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
        PostgreSQL+PostGIS · Redis · Stockage S3 · FCM · SMS/Email · PSP · LLM · Cartes
```

**Les cinq idées structurantes du blueprint**

1. **Monolithe modulaire strict** : frontières de modules appliquées par l'outillage (pas par la discipline), extraction possible plus tard.
2. **Trois classes de données** : _tenant-privées_ (Business, isolées par RLS), _user-privées_ (Money, IA, candidatures) et _publiques/partagées_ (annonces, profils). Chaque table appartient à une seule classe.
3. **Événements transactionnels (outbox)** : les effets inter-modules sont asynchrones et idempotents ; les invariants d'un même module restent dans la même transaction.
4. **Offline par journal de commandes** (pas par réplication d'état) : une vente faite hors-ligne est un fait, jamais écrasé silencieusement.
5. **La base et le code métier sont la source de vérité** — jamais le frontend, jamais le LLM, jamais un « success » client pour un paiement.

---

## 2. Carte du blueprint (les 27 points demandés)

| #   | Point demandé                                                                       | Document                                                                                |
| --- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 1   | Architecture globale                                                                | [02-architecture.md](02-architecture.md)                                                |
| 2   | Architecture frontend                                                               | [02-architecture.md](02-architecture.md) §7                                             |
| 3   | Architecture backend                                                                | [02-architecture.md](02-architecture.md) §4–5                                           |
| 4   | Architecture DB                                                                     | [03-database.md](03-database.md)                                                        |
| 5   | Diagramme des relations                                                             | [03-database.md](03-database.md) §5                                                     |
| 6   | Architecture API                                                                    | [05-api.md](05-api.md)                                                                  |
| 7   | Architecture IA                                                                     | [07-ai.md](07-ai.md)                                                                    |
| 8   | Architecture paiements                                                              | [06-platform-engines.md](06-platform-engines.md) §1                                     |
| 9   | Architecture notifications                                                          | [06-platform-engines.md](06-platform-engines.md) §2                                     |
| 10  | Architecture offline                                                                | [08-offline-sync.md](08-offline-sync.md)                                                |
| 11  | Authentification                                                                    | [04-identity-access.md](04-identity-access.md) §2–3                                     |
| 12  | RBAC                                                                                | [04-identity-access.md](04-identity-access.md) §4                                       |
| 13  | Multi-tenant                                                                        | [04-identity-access.md](04-identity-access.md) §5 · [03-database.md](03-database.md) §6 |
| 14  | Abonnements                                                                         | [04-identity-access.md](04-identity-access.md) §6                                       |
| 15  | Recherche                                                                           | [06-platform-engines.md](06-platform-engines.md) §4                                     |
| 16  | Messagerie                                                                          | [06-platform-engines.md](06-platform-engines.md) §3                                     |
| 17  | Modération (+ vérification, avis)                                                   | [06-platform-engines.md](06-platform-engines.md) §5–7                                   |
| 18  | Architecture admin                                                                  | [09-admin.md](09-admin.md)                                                              |
| 19  | Stratégie de tests                                                                  | [10-testing.md](10-testing.md)                                                          |
| 20  | Stratégie DevOps                                                                    | [12-devops-monitoring.md](12-devops-monitoring.md) §1–4                                 |
| 21  | Stratégie sécurité                                                                  | [11-security.md](11-security.md)                                                        |
| 22  | Stratégie monitoring                                                                | [12-devops-monitoring.md](12-devops-monitoring.md) §5                                   |
| 23  | Structure exacte des dossiers                                                       | [13-repository-structure.md](13-repository-structure.md)                                |
| 24  | Roadmap Phase 0 → 11                                                                | [14-roadmap-risks.md](14-roadmap-risks.md) §1                                           |
| 25  | Dépendances entre modules                                                           | [02-architecture.md](02-architecture.md) §8                                             |
| 26  | Risques techniques                                                                  | [14-roadmap-risks.md](14-roadmap-risks.md) §3                                           |
| 27  | Complexité par module                                                               | [14-roadmap-risks.md](14-roadmap-risks.md) §4                                           |
| —   | **Décisions d'architecture (options / avantages / inconvénients / recommandation)** | [01-decisions.md](01-decisions.md)                                                      |

Ordre de lecture conseillé : ce fichier → **01-decisions** → 02 → 03 → 14.

---

## 3. Hypothèses de travail (à corriger si fausses)

| #   | Hypothèse                                                                                                                                                                      | Conséquence si fausse                                              |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| H1  | Marché initial : **Guinée**, puis Afrique de l'Ouest francophone. Langue par défaut : français. Pays, devise, fuseau, formats sont **configurables** (aucun « GNF » en dur).   | Revoir la sélection PSP/SMS, la région cloud et les textes légaux. |
| H2  | **Android en priorité** (parc dominant, smartphones modestes) ; iOS livré via Flutter mais validé un cran derrière.                                                            | Inverser la priorité des tests de performance.                     |
| H3  | **Connectivité instable et data chère** → offline-first pour Business, charges utiles légères, images optimisées.                                                              | Budgets de performance moins stricts.                              |
| H4  | **Mobile money** = moyen de paiement dominant ; cartes marginales. Pas de prélèvement récurrent automatique fiable.                                                            | Le modèle d'abonnement (relances plutôt qu'auto-débit) change.     |
| H5  | **Équipe de référence ≈ 8 personnes** (2 Flutter, 3 backend, 1 designer, 1 QA, 0,5 DevOps, 1 PM/BA) pour les estimations.                                                      | Toutes les durées de la roadmap sont à recalibrer.                 |
| H6  | Poste de dev actuel : Windows 11 + Docker Desktop + Node + Flutter présents ; **pnpm et JDK absents** (à installer en Phase 0) ; **build iOS impossible en local → CI macOS**. | —                                                                  |
| H7  | Le blueprint prévoit les **mécanismes techniques** de conformité (données perso, paiement, immobilier, emploi, mineurs). Il ne remplace pas un **avis juridique local**.       | Risque réglementaire non couvert (voir risques R3, R10).           |

---

## 4. Écarts assumés par rapport au brief

Le brief demandait explicitement de **revoir** la structure avant implémentation. Voici ce qui change, et pourquoi.

| Sujet                 | Brief                                                                | Blueprint                                                                                                                  | Raison                                                                                                                                        |
| --------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Modules backend §7    | `/roles`, `/permissions`, `/products`, `/orders`, `/payments` à plat | `rbac` unique ; `products/inventory/orders` **dans** `business` ou `marketplace` ; `payments` = moteur de plateforme       | Évite 25 modules plats sans frontières ; une commande POS ≠ une commande Marketplace.                                                         |
| Tables §8             | ~60 tables listées                                                   | Liste **rationalisée** (fusions, renommages, ajouts) — voir [03-database.md](03-database.md) §2                            | `customers`+`suppliers` → `contacts` ; `transporters` = `drivers` ; `invoices` → `billing.invoices` (collision avec factures de vente) ; etc. |
| `sync_queue`          | Table serveur                                                        | **Structure côté client** (SQLite). Côté serveur : `idempotency_keys` + `sync_conflicts`                                   | Une file de synchro vit là où les données sont écrites hors-ligne.                                                                            |
| Paiements             | « `payments` »                                                       | **Deux concepts** : encaissement POS déclaré (`biz.sale_payments`) vs paiement collecté par la plateforme (`pay.payments`) | Un commerçant qui note « payé en espèces » n'est pas un paiement THY. Ne jamais confondre déclaré et confirmé.                                |
| Argent                | non précisé                                                          | **Grand livre à double entrée** (`pay.ledger_*`) + montants en **unités mineures** (BIGINT)                                | Marketplace/Services/Agro = flux à 3 parties, commissions, remboursements.                                                                    |
| Identité staff        | Admin RBAC                                                           | Comptes **staff séparés** des comptes clients (SSO + MFA obligatoire)                                                      | Un compte client compromis ne doit jamais ouvrir l'admin.                                                                                     |
| Livraison externe §16 | « entreprise externe »                                               | **API keys + webhooks sortants** (Phase 4)                                                                                 | Nécessite une authentification machine-à-machine absente du brief.                                                                            |
| Freelance (Jobs) §18  | Fonction Jobs                                                        | Modélisé comme **type de service à distance** (Services) + portfolio Jobs                                                  | Évite un second moteur de mise en relation client↔pro.                                                                                        |
| Ordre des moteurs     | —                                                                    | Chaque moteur (messagerie, avis, recherche…) est **construit au premier consommateur** (Phase 3), pas en Phase 0           | Pas de sur-ingénierie spéculative. Exception : identité, tenancy, RBAC, audit, notifications de base en Phase 0.                              |
| Paiement réel         | Phase 3 implicite                                                    | **Premier PSP réel en fin de Phase 1** (abonnements uniquement)                                                            | Deux phases de durcissement avant d'y brancher l'argent des commandes.                                                                        |
| Jalons de livraison   | 11 phases                                                            | **3 jalons de release** (privé après Ph.1, public v1 après Ph.4, complet après Ph.11)                                      | Valeur réelle et retours utilisateurs tôt.                                                                                                    |

---

## 5. Décisions qui exigent ton arbitrage

Les options complètes sont dans [01-decisions.md](01-decisions.md). Voici ce qui **bloque le démarrage** de la Phase 0, avec ma recommandation par défaut.

| #   | Décision          | Recommandation                                                                                                                                                                | Bloquant pour         |
| --- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| D1  | Style backend     | **Monolithe modulaire** NestJS, 3 processus (api / worker / migrate)                                                                                                          | Toute la Phase 0      |
| D2  | Accès données     | **Drizzle + migrations SQL revues**, après spike de 2 jours (PostGIS + RLS) ; repli Kysely                                                                                    | Kernel DB             |
| D3  | Offline           | **Drift (SQLite chiffré) + journal de commandes**, spike 1 semaine vs PowerSync                                                                                               | Phase 1               |
| D4  | Hébergement       | **Validé : GCP** — Cloud Run + Cloud SQL (PostGIS) + Memorystore + Cloud Storage, région à confirmer par mesure de latence réelle (`europe-west1`/`europe-west4` pressenties) | Staging Phase 0       |
| D5  | SMS / OTP         | 2 fournisseurs + repli WhatsApp/voix ; **test de délivrabilité** sur réseaux locaux                                                                                           | Auth Phase 0          |
| D6  | PSP               | Diligence non-code dès la Phase 0 (agrégateur mobile money) ; **THY ne détient pas de fonds**                                                                                 | Fin Phase 1           |
| D7  | LLM               | Abstraction + **un fournisseur principal + un repli**, choisis sur un **jeu d'évaluation THY** (français, tool-calling, vision)                                               | Phase 2               |
| D8  | Cartes            | Abstraction `GeoProvider` + MapLibre ; comparer tuiles OSM vs Google sur la Guinée                                                                                            | Phase 3–4             |
| D9  | Admin web         | **React + Vite + TypeScript** (SPA)                                                                                                                                           | Phase 0 (shell)       |
| D10 | Identité visuelle | Logo, couleur primaire, ton de marque **à fournir** — le blueprint fixe la structure des tokens, pas la palette                                                               | Design system Phase 0 |
| D11 | Jalons            | Adopter les 3 jalons de release (§4)                                                                                                                                          | Roadmap               |

> **Statut (2026-09-22)** : blueprint et décisions D1–D11 validés par l'utilisateur. Plan détaillé de la Phase 0 : [docs/plans/phase-0-foundation.md](../plans/phase-0-foundation.md).
>
> **Mise à jour importante** : l'audit de Phase 0 a révélé du code existant substantiel pour Business, Academy et Services (hors de ce dépôt). Ce n'est plus un projet greenfield pour ces trois modules — voir [docs/plans/consolidation-strategy.md](../plans/consolidation-strategy.md) et [ADR-018](01-decisions.md#adr-018--découverte-de-code-existant--stratégie-de-consolidation-2026-09-22).

---

## 6. Principes de conception (rappel opérationnel)

1. **Sécurité serveur d'abord** : aucun identifiant, prix, total ou statut de paiement fourni par le client n'est cru.
2. **Un module = une frontière** : import uniquement via `contracts/` ; pas de jointure SQL entre modules sauf lecture déclarée.
3. **Fail closed** : contexte tenant absent ⇒ zéro ligne ; permission inconnue ⇒ refus ; LLM en erreur ⇒ réponse déterministe ou aveu d'incertitude.
4. **Tout ce qui est important est append-only** : ventes, mouvements de stock, écritures comptables, audit.
5. **Ne jamais présenter comme réel ce qui ne l'est pas** : « Vérifié » n'existe qu'après une revue humaine tracée ; un paiement n'existe qu'après confirmation serveur.
6. **Pas de donnée fictive en production** ; pas de secret dans le dépôt ; pas de donnée sensible dans les logs.
7. **Un module n'est « terminé » qu'avec ses tests, sa doc, ses dashboards/alertes et son threat model** (Definition of Done : [10-testing.md](10-testing.md) §8).

## 7. Glossaire minimal

| Terme               | Sens dans THY                                                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **Persona**         | Capacité activée sur un compte (client, vendeur, pro, candidat, étudiant, agriculteur, livreur…). Ce n'est pas une permission. |
| **Tenant**          | Une `business`. Frontière d'isolation des données Business.                                                                    |
| **Moteur**          | Service de plateforme réutilisé par plusieurs modules (paiement, messagerie…).                                                 |
| **Facade**          | API publique typée d'un module (`contracts/`). Seul point d'entrée inter-modules.                                              |
| **Outbox**          | Table d'événements écrits dans la même transaction que la donnée métier, publiés ensuite.                                      |
| **Entitlement**     | Droit d'usage d'une fonctionnalité/quota issu d'un abonnement (≠ permission RBAC).                                             |
| **Commande (sync)** | Intention métier enregistrée hors-ligne (`sales.create`) rejouée au serveur avec idempotence.                                  |
