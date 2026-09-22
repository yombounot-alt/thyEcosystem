# 14 — Roadmap, risques, complexité

Couvre les points 24, 26 et 27 (le point 25 « dépendances » est dans [02 §8](02-architecture.md)).

> Durées = **ordre de grandeur pour l'équipe de référence (≈ 8 personnes, H5)**, en semaines calendaires. À **recalibrer après la Phase 0** avec la vélocité mesurée. Ce sont des estimations, pas des engagements.

---

## 1. Roadmap Phase 0 → Phase 11

### Règle d'entrée de chaque phase (brief §41)

1. Inspecter code, DB, API, composants UI existants. 2. Identifier les dépendances. 3. **Proposer un plan détaillé.** 4. **Attendre validation** si une décision d'architecture importante apparaît. 5. Ne rien détruire ni réécrire sans raison.

### Jalons de release

| Jalon                       | Après                     | Contenu                                                         | Valeur                                                                |
| --------------------------- | ------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------- |
| **R1 — Bêta privée**        | Phase 1 (+ Phase 2 léger) | Business POS offline + abonnements, pilote de commerçants réels | Valider le cœur de valeur et l'offline **avec de vrais utilisateurs** |
| **R2 — Public v1**          | Phase 4                   | + IA Business, Marketplace, Delivery                            | Écosystème d'échange complet (offre ← Business)                       |
| **R3 — Écosystème complet** | Phase 11                  | Tous les modules intégrés et optimisés                          | Vision « Super App »                                                  |

---

### PHASE 0 — Foundation · ≈ 8–10 sem.

**Objectif** : fondations techniques et de confiance ; **aucun module métier**.
**Lots**

| Lot                       | Contenu                                                                                                                                                                                             |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L0.1 Dépôt & outillage    | Monorepo, pnpm/Turborepo/Melos, lint, hooks (gitleaks, commits), conventions                                                                                                                        |
| L0.2 Environnement local  | `compose.dev.yml` (PG+PostGIS, Redis, MinIO, Mailpit, OTel), scripts, `.env.example`                                                                                                                |
| L0.3 CI/CD squelette      | Pipelines PR, sécurité, build, déploiement staging, environnement prod protégé                                                                                                                      |
| L0.4 Infra staging (IaC)  | Conteneurs, PG/Redis managés, S3, secrets, CDN/WAF, observabilité de base                                                                                                                           |
| L0.5 Kernel backend       | Config validée, DB/tx/RLS, outbox/événements/files, pipeline HTTP, erreurs, health, i18n, logs/traces                                                                                               |
| L0.6 Identité             | `auth`, `users`, sessions, appareils, OTP (2 fournisseurs SMS), anti-abus, `audit`                                                                                                                  |
| L0.7 Tenancy & RBAC       | `businesses`, lieux, membres, invitations, `rbac`, tests de fuite, lint de schéma                                                                                                                   |
| L0.8 Plateforme de base   | `subscriptions` (squelette + flags), `notifications` (in-app + push), `media` (upload sécurisé)                                                                                                     |
| L0.9 Design system        | Tokens, thèmes clair/sombre, composants, états vides/chargement/erreur, Widgetbook, goldens                                                                                                         |
| L0.10 App Flutter (shell) | Flavors, bootstrap, ModuleRegistry, navigation adaptative, accueil squelette, onboarding → OTP → profil → création de business, i18n fr/en, client API généré                                       |
| L0.11 Admin (shell)       | SSO/MFA staff, RBAC, Users, Audit, System settings de base                                                                                                                                          |
| L0.12 Documentation       | README, ARCHITECTURE, DATABASE, API, SECURITY, DEPLOYMENT, TESTING, CONTRIBUTING, CHANGELOG, ADR validés                                                                                            |
| **Spikes (timeboxés)**    | S1 Drizzle+PostGIS+RLS (2 j) · S2 prototype sync Drift↔API (3–5 j) · S3 délivrabilité OTP sur réseaux locaux (continu) · S4 base de performance appareil bas de gamme · S5 diligence PSP (non-code) |

**Critères de sortie** : inscription OTP sur **appareil réel** en staging ; création d'entreprise + invitation + rôles ; **tests de fuite tenant verts** ; CI complète verte ; observabilité active (erreurs, traces, dashboards, alertes de base) ; galerie du design system ; docs et ADR à jour ; **aucun secret dans le dépôt**.
**Risques clés** : sur-ingénierie du kernel ; délivrabilité SMS ; dérive du design system.

### PHASE 1 — THY Business · ≈ 16–20 sem.

**Périmètre** : produits/catégories/unités ; **stock** (mouvements, niveaux, alertes, inventaire) ; contacts (clients/fournisseurs) ; **caisse** (sessions, ventes, multi-règlements, retours, reçus, numérotation par appareil) ; **crédits** créances/dettes ; achats ; dépenses ; employés (fiche RH) ; **rapports** (agrégats quotidiens, marge CMP) ; rôles/permissions Business ; notifications (stock bas, résumé quotidien) ; **abonnements FREE/PRO** ; **offline complet + sync + boîte de conflits** ; admin (Businesses, Subscriptions).
**Fin de phase** : **payments v1 (abonnements uniquement)** avec le premier PSP réel _(coupe-feu : si retard, activation manuelle des abonnements pendant la bêta)_.
**Hors périmètre** : Marketplace, IA, paiement de commandes, multi-devises avancé, paie.
**Critères de sortie** : S1 et S4/S5 (E2E) verts ; simulations de convergence de sync au vert ; budgets de perf tenus sur appareil cible ; pilote de commerçants opérationnel (**Jalon R1**).
**Risques** : **sync/offline** (le plus dur du projet) ; adoption ; numérotation légale.

### PHASE 2 — THY AI · ≈ 6–8 sem.

`ai-gateway`, registre d'outils, pipeline complet (autorisation par outil, ancrage des chiffres, validation), outils Business en **lecture + brouillons**, chat en streaming, quotas par entitlement, jeux d'évaluation, tableaux de bord de coût, consentements IA.
**Sortie** : réponses **strictement conformes** aux rapports déterministes ; tests d'injection et d'autorisation verts ; coûts suivis. **Dépend de** : Phase 1 (données à analyser), ADR-013.

### PHASE 3 — THY Marketplace · ≈ 12–14 sem.

**Moteurs construits ici** : `search`, `messaging`, `reviews`, `verification` (vendeur), `moderation`/signalements/blocage, `engagement` (favoris), `support` de base, **paiements de commandes** (PSP, ledger, réconciliation, séquestre selon validation juridique), `geo` de base.
**Métier** : boutiques (particulier ou Business), **publication Business → listing** (liaison produit, disponibilité reliée au stock, réservation), catalogue/catégories, panier, checkout (process manager), commandes, avis autorisés ; retrait/livraison par le vendeur (Delivery arrive en Phase 4).
**Sortie** : S2/S3 verts ; réconciliation quotidienne opérationnelle ; modération en place (exigence des stores UGC).
**Risques** : PSP/réglementation ; surstock (vente magasin vs en ligne) ; démarrage à froid (offre issue de Business).

### PHASE 4 — THY Delivery · ≈ 8–10 sem.

Livreurs (persona + vérification), véhicules, missions, **machine d'états serveur** (CREATED→…→DELIVERED/FAILED/CANCELLED), assignation (manuelle puis automatique), suivi temps réel, preuve de livraison (code/photo/géo), tarifs, **COD et remise de caisse**, création depuis Marketplace/Business/**API partenaire (API keys + webhooks sortants)**.
**Sortie** : **Jalon R2 (public v1)** après **test d'intrusion externe** et test de charge.

### PHASE 5 — THY Services · ≈ 10–12 sem.

Profils pro, compétences, portfolio, zones (PostGIS), disponibilités (contraintes d'exclusion), demandes → devis → réservations, messagerie, paiement séquestré, avis liés à la prestation, litiges, vérification pro. **Freelance** = services à distance.

### PHASE 6 — THY Immo · ≈ 6–8 sem.

Biens/annonces, photos/vidéos, carte et recherche géo, favoris/alertes, visites, contact, **cycle DRAFT→PENDING_REVIEW→VERIFIED/REJECTED/SUSPENDED/ARCHIVED** avec **contrainte DB de vérification humaine**, signalements, prévention des arnaques.

### PHASE 7 — THY Jobs · ≈ 8–10 sem.

Profils candidats/CV, offres (employeurs = Business vérifiés), candidatures avec historique, favoris/alertes, messagerie, **correspondance IA explicable sans décision automatique**, garde-fous d'équité, portfolio/freelance.

### PHASE 8 — THY Agro · ≈ 6–8 sem.

Producteurs, référentiel de cultures, offres (quantité, unité configurable, disponibilité, prix), commandes, **fret via Delivery (`FREIGHT`)**, preuve de livraison, litiges, notifications ; acomptes encadrés (anti-arnaque).

### PHASE 9 — THY Money · ≈ 5–7 sem.

Comptes personnels, revenus/dépenses, catégories, budgets, objectifs, rappels, statistiques, **offline**, RLS utilisateur, import volontaire depuis Business, consentement pour l'IA. **Mention claire : THY Money n'est pas une banque.** Tout paiement réel ultérieur passe par des prestataires agréés.

### PHASE 10 — THY Academy · ≈ 10–14 sem.

Cours/matières/leçons/documents, **vidéo HLS externe**, exercices/QCM/examens, progression et statistiques, **téléchargement hors-ligne**, outils d'auteur (admin/instructeur), **pipeline vision Academy** avec vérification indépendante, protection des mineurs, **décision sur la facturation des contenus numériques dans les stores** (R9).

### PHASE 11 — Intégration et optimisation · ≈ 8–12 sem.

Parcours transverses (Business→Marketplace→Delivery→Money→AI), accueil personnalisé, recherche globale affinée, **audit de performance et de coûts**, réplica de lecture, **test d'intrusion externe #2**, exercice de reprise après sinistre, audit d'accessibilité, complétude i18n, export/effacement des données, gel documentaire, préparation du lancement.

### Vue calendrier (séquentiel ; parallélisable en 2 squads dès la Phase 5)

```
P0 ▇▇▇▇▇▇▇▇▇
P1          ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇  ── R1 bêta privée
P2                            ▇▇▇▇▇▇▇
P3                                   ▇▇▇▇▇▇▇▇▇▇▇▇
P4                                                ▇▇▇▇▇▇▇▇▇  ── R2 public v1
P5..P10 (2 squads)                                          ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇
P11                                                                                  ▇▇▇▇▇▇▇▇▇▇ ── R3
```

Total séquentiel ≈ **103–133 semaines** ; ≈ 30 % de réduction possible avec deux squads à partir de la Phase 5.

---

## 2. Dépendances entre phases

| Phase | Dépend de                | Fournit à                                                                         |
| ----- | ------------------------ | --------------------------------------------------------------------------------- |
| 0     | —                        | toutes                                                                            |
| 1     | 0                        | 2 (données), 3 (produits/stock), 7 (identité employeur)                           |
| 2     | 0, 1                     | 3–10 (nouveaux outils)                                                            |
| 3     | 0, 1                     | 4, 5, 6, 7, 8 (moteurs search/messaging/reviews/verification/moderation/payments) |
| 4     | 3 (commandes, paiements) | 8 (fret)                                                                          |
| 5     | 3 (moteurs)              | —                                                                                 |
| 6     | 3                        | —                                                                                 |
| 7     | 1, 2, 3                  | —                                                                                 |
| 8     | 3, 4                     | —                                                                                 |
| 9     | 0 (+2 pour l'IA)         | —                                                                                 |
| 10    | 0, 2 (vision)            | —                                                                                 |
| 11    | toutes                   | R3                                                                                |

---

## 3. Risques techniques

Échelle : Probabilité (P) / Impact (I) = Faible · Moyenne · Élevée.

| #   | Risque                                                                                                         | P   | I   | Mitigation                                                                                                                       | Phase  |
| --- | -------------------------------------------------------------------------------------------------------------- | --- | --- | -------------------------------------------------------------------------------------------------------------------------------- | ------ |
| R1  | **Explosion de périmètre** (10 modules)                                                                        | É   | É   | Phasage strict, moteurs construits au premier consommateur, jalons R1/R2/R3, revue de périmètre à chaque phase, critères d'arrêt | Toutes |
| R2  | **Sync offline incorrecte** (perte, doublon, conflits mal gérés)                                               | M   | É   | Protocole par commandes idempotentes, IDs client, simulation déterministe, spike Phase 0, pilote R1, boîte de conflits           | 0–1    |
| R3  | **Réglementation paiements** (collecte pour tiers, séquestre, KYC/LCB-FT)                                      | M   | É   | Ne pas détenir de fonds ; PSP agréé ; conseil juridique avant Phase 3 ; `PaymentProvider` abstrait                               | 0–3    |
| R4  | **Fiabilité/coût du PSP mobile money**, webhooks perdus, litiges                                               | É   | É   | Idempotence, `fetchStatus`, réconciliation quotidienne, alertes, second fournisseur possible                                     | 1–3    |
| R5  | **Fuite de données inter-tenant**                                                                              | F   | É   | RLS + FK composites + tests générés + lint de schéma + revues                                                                    | 0+     |
| R6  | **Performance sur appareils modestes/réseaux lents**                                                           | É   | É   | Budgets, tests sur appareil réel, images optimisées, pagination, composants différés, offline                                    | 0+     |
| R7  | **Délivrabilité et coût des SMS OTP** (SMS pumping)                                                            | É   | M   | 2 fournisseurs + repli WhatsApp/voix, attestation d'appareil, plafonds de coût                                                   | 0      |
| R8  | **LLM : hallucination, coût, latence, injection, langues locales**                                             | É   | M   | Ancrage des chiffres, outils autorisés, quotas, repli, évaluations, périmètre honnête FR/EN                                      | 2      |
| R9  | **Règles des stores** : paiement des biens numériques ; obligations UGC                                        | M   | M   | Vérifier avant Phase 10 ; modération/signalement/blocage dès Phase 3                                                             | 3, 10  |
| R10 | **Conformité données personnelles / mineurs / secteurs**                                                       | M   | É   | Minimisation, consentements, rétention, export/effacement ; validation juridique locale                                          | 0+     |
| R11 | **Fraude et arnaques** (fausses annonces, faux avis, acomptes)                                                 | É   | É   | Vérification humaine, `VERIFIED` contraint en DB, avis liés à interaction, modération, détection de doublons                     | 3–8    |
| R12 | **Démarrage à froid Marketplace**                                                                              | É   | M   | Offre alimentée par Business ; lancement local par zones ; vendeurs pilotes                                                      | 3      |
| R13 | **Surstock / incohérences** entre vente magasin et en ligne                                                    | É   | M   | Réservations avec TTL, tampon de stock publié, drapeaux `needs_review`, alertes                                                  | 1–3    |
| R14 | **Latence/hébergement** vers l'Afrique de l'Ouest et résidence des données                                     | M   | M   | Mesure réelle avant de figer la région, CDN, payloads légers                                                                     | 0      |
| R15 | **Dépendance à l'équipe** (bus factor) et **largeur de la pile** (Flutter, Nest, React, PG/PostGIS, Redis, IA) | M   | É   | Docs/ADR, revues croisées, standards, formation, limiter les technologies                                                        | 0+     |
| R16 | **Clients mobiles anciens** qui persistent                                                                     | É   | M   | `min_supported_version`, API additive, dépréciations planifiées                                                                  | 1+     |
| R17 | **Qualité des données géo** (adressage informel, tuiles)                                                       | M   | M   | Pin GPS + repère, comparaison OSM/Google, tests terrain                                                                          | 3–6    |
| R18 | **Coût vidéo/bande passante Academy**                                                                          | M   | M   | Plateforme HLS externe, débit adaptatif, téléchargement explicite                                                                | 10     |
| R19 | **Complexité fiscale / numérotation légale / multi-pays**                                                      | M   | M   | Configuration par pays, validation juridique, périmètre initial mono-pays                                                        | 1, 11  |
| R20 | **Sur-ingénierie** (kernel, abstractions prématurées)                                                          | M   | M   | Construire au premier consommateur ; revue « YAGNI » ; ports seulement aux vraies frontières externes                            | 0      |
| R21 | **Fraude interne** (caissiers, staff)                                                                          | M   | É   | Permissions fines, seuils, audit, 4-yeux, revues d'accès                                                                         | 1+     |
| R22 | **Build iOS sans Mac local**                                                                                   | F   | F   | CI macOS, TestFlight                                                                                                             | 0      |

---

## 4. Complexité par module

Notation 1 (faible) → 5 (très élevée). _Domaine_ = richesse des règles métier ; _Technique_ = difficulté d'ingénierie ; _Ext._ = dépendance à des tiers ; _Réglem./Risque_ = exposition légale/fraude.

| Module                     | Domaine | Technique | Ext. | Réglem./Risque | **Global** | Effort (sem., équipe réf.) | Points de difficulté principaux                                             |
| -------------------------- | :-----: | :-------: | :--: | :------------: | :--------: | -------------------------- | --------------------------------------------------------------------------- |
| **Phase 0 — Foundation**   |    3    |     5     |  2   |       4        |   **4**    | 8–10                       | RLS, kernel, auth, CI/IaC, design system                                    |
| **Business**               |    5    |     5     |  2   |       3        |   **5**    | 16–20                      | **Offline/sync**, stock cohérent, caisse, rapports, numérotation            |
| **AI**                     |    3    |     4     |  3   |       4        |   **4**    | 6–8                        | Autorisation par outil, ancrage des chiffres, évaluations, coûts            |
| **Marketplace**            |    4    |     4     |  4   |       4        |   **5**    | 12–14                      | Paiements + ledger + séquestre, checkout saga, moteurs partagés, modération |
| **Delivery**               |    4    |     4     |  3   |       3        |   **4**    | 8–10                       | Temps réel/géo, machine d'états, COD, API partenaire                        |
| **Services**               |    4    |     3     |  3   |       3        |   **4**    | 10–12                      | Devis/réservations, disponibilité, séquestre, litiges                       |
| **Immo**                   |    3    |     3     |  2   |       4        |   **3**    | 6–8                        | Anti-arnaque, modération, vérification humaine, géo                         |
| **Jobs**                   |    3    |     3     |  1   |       3        |   **3**    | 8–10                       | Équité de l'IA, données CV, pipeline de candidatures                        |
| **Agro**                   |    3    |     2     |  2   |       2        |   **3**    | 6–8                        | Unités configurables, fret, acomptes, saisonnalité                          |
| **Money**                  |    2    |     2     |  1   |       4        |  **2–3**   | 5–7                        | Confidentialité, offline, positionnement « pas une banque »                 |
| **Academy**                |    4    |     4     |  4   |       3        |   **4**    | 10–14                      | Vidéo, vision + vérification, offline, mineurs, règles des stores           |
| **Phase 11 — Intégration** |    3    |     4     |  2   |       3        |   **4**    | 8–12                       | Parcours transverses, coûts, audits externes                                |

**Moteurs transverses (inclus dans les phases ci-dessus)** : paiements+ledger (élevée), sync (très élevée), messagerie (moyenne), recherche (moyenne), vérification/modération (moyenne, forte composante opérationnelle), notifications (moyenne), avis (faible-moyenne).

---

## 5. Prochaine étape après validation

1. Arbitrages **D1–D11** ([README §5](README.md)).
2. Rédaction du **plan détaillé de la Phase 0** (lots, tâches, critères, ordre, risques) — **validation avant tout code**.
3. Démarrage de la Phase 0 : dépôt/outillage → environnement local → kernel → identité → tenancy/RBAC → design system → shells mobile/admin → documentation.
