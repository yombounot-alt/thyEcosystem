# 10 — Stratégie de tests

Couvre le point 19. Règle absolue du brief : **aucun module n'est « terminé » sans tests.**

---

## 1. Pyramide et outils

| Niveau | Cible | Outils proposés | Exécution |
|---|---|---|---|
| **Unitaire** | Services, règles métier, machines d'états, calculs monétaires, politiques RBAC | Vitest/Jest (backend), `test` + `mocktail` (Dart) | Chaque PR (< 3 min) |
| **Propriétés** | Argent, machines d'états, sync (convergence), calcul de stock/CMP | `fast-check` (TS), `glados` (Dart) | Chaque PR |
| **Intégration** | API + PostgreSQL/PostGIS + Redis réels | **Testcontainers** (PG + PostGIS, Redis, MinIO) + Supertest | Chaque PR |
| **Contrat** | Réponses vs OpenAPI ; compatibilité N-1 ; événements vs schémas | Validation de schéma, `oasdiff`, Schemathesis (staging) | PR + nocturne |
| **Isolation / sécurité** | RLS, autorisation par route, fuite inter-tenant | Suites générées depuis le catalogue PG et le registre de routes | Chaque PR |
| **E2E API** | Parcours complets | Supertest + scénarios | Staging, chaque merge |
| **UI Flutter** | Widgets, golden (clair/sombre, échelle de texte), accessibilité | `flutter_test`, goldens, Widgetbook | Chaque PR |
| **E2E mobile** | Parcours sur émulateur/appareil | Patrol ou `integration_test` + Maestro | Nocturne + pré-release |
| **Performance** | Charge API, démarrage app, sync massive | k6 ; profils Flutter sur appareil bas de gamme | Hebdo + pré-release |
| **Résilience** | Panne PSP/SMS/LLM/Redis, latence | Fault injection (Toxiproxy) | Pré-release |

## 2. Couverture : qualité avant pourcentage
- Seuils **par zone critique** (kernel, auth, rbac, payments/ledger, sync, tenancy, IA/outils) : **≥ 85 % lignes ET branches** ; global indicatif ≥ 70 %.
- **Tests de mutation** (Stryker) sur `payments`, `ledger`, machines d'états, calcul de stock : le score compte plus que la couverture.
- Chaque bug corrigé ⇒ **test de non-régression** obligatoire.

## 3. Tests de sécurité automatisés (bloquants)

| Test | Vérifie |
|---|---|
| **Fuite multi-tenant** | Pour toute table tenant : RLS + `FORCE` ; sous A, 0 ligne de B ; insertion croisée refusée ; FK composite ; contexte absent ⇒ 0 ligne |
| **Registre de routes** | Chaque route déclare `@Public()` ou une politique ; sinon échec |
| **Matrice rôle × route** | Générée : chaque rôle (client, membre par rôle, staff par rôle, machine) × chaque route ⇒ statut attendu (200/403/404) |
| **BOLA/IDOR** | Identifiants d'un autre utilisateur/tenant sur chaque ressource ⇒ refus |
| **Mass assignment** | Champs non déclarés rejetés |
| **Idempotence** | Rejouer chaque POST sensible ⇒ un seul effet |
| **Paiement** | Webhook forgé/rejoué/montant altéré ⇒ rejet ; « success » client sans confirmation ⇒ aucun effet |
| **OTP** | Brute force, énumération, renvois, expirations |
| **Sessions** | Réutilisation de refresh ⇒ révocation de famille ; déconnexion globale effective |
| **Uploads** | Faux MIME, fichier piégé, EXIF, taille |
| **Secrets/logs** | Scan des sorties de test : aucun secret/PII dans les logs (test de redaction) |

## 4. Scénarios E2E de référence

**S1 — Commerçant (brief §39)** : inscription → OTP → création d'entreprise → invitation d'un caissier → produit → stock initial → **vente hors-ligne** → synchronisation → reçu → rapport du jour → vérification que le stock, le CA et la marge sont exacts, et qu'aucune donnée n'est visible d'un autre tenant.

**S2 — Client Marketplace** : client → recherche → panier → commande → paiement (**webhook de test signé**) → confirmation serveur → création de livraison → affectation livreur → événements → livraison avec code/preuve → avis autorisé → versement au vendeur (après fenêtre).

**S3 — Échec de paiement** : expiration/échec ⇒ commande annulée, **stock libéré**, aucune écriture comptable, notification.

**S4 — Conflit de sync** : deux appareils modifient le prix d'un même produit hors-ligne ⇒ conflit présenté, aucune perte silencieuse.

**S5 — Vente sur stock épuisé (hors-ligne)** : acceptée + drapeau `needs_review` + alerte gérant.

**S6 — Services** : demande → devis → réservation → paiement séquestré → prestation → avis → litige → résolution.

**S7 — Vérification** : demande → revue staff → `VERIFIED` (contrainte DB) → badge visible ; refus ⇒ jamais de badge.

**S8 — IA** : question sur les ventes ⇒ chiffres **identiques** au rapport déterministe ; tentative d'accès à un autre tenant ⇒ refus ; injection dans une description produit ⇒ ignorée.

**S9 — Récupération de compte** : perte du téléphone ⇒ délais, notifications, révocation.

## 5. Données de test
- **Fabriques** (`factories`) par module ; **aucune donnée de production** ; scripts d'anonymisation si un snapshot est nécessaire en staging.
- **Seeds « démo »** protégés par garde technique : impossibles à exécuter en production.
- **Horloge injectable** (`Clock` port) pour tester expirations, TTL, fuseaux et fenêtres de sync.

## 6. Performance et charge (objectifs à valider)

| Scénario | Objectif indicatif |
|---|---|
| Vente (POST) | p95 < 300 ms |
| Liste produits (20) | p95 < 200 ms |
| Recherche globale | p95 < 400 ms |
| `sync/push` 100 commandes | p95 < 3 s, 0 perte |
| Checkout (sans PSP) | p95 < 600 ms |
| Diffusion WS 1 000 clients | livraison < 1 s |
Charge de départ : 10× la cible de lancement ; profil de **réseau dégradé** (latence élevée, pertes).

## 7. Tests IA
- **Outils** testés **sans LLM** (entrées/sorties déterministes, autorisation, plafonds de lignes, expurgation).
- **Autorisation** : le LLM (simulé) tente un outil non autorisé / un `business_id` étranger ⇒ refus.
- **Ancrage des chiffres** : toute réponse dont un nombre ne provient pas d'une variable est rejetée (jeux de cas).
- **Injection** : corpus d'attaques (produits, messages, CV, images) ⇒ aucune fuite ni action non autorisée.
- **Évaluation** : jeux dorés FR par intention ; seuils de régression ; revue humaine périodique ; suivi des coûts.

## 8. Definition of Done — module
Un module n'est terminé que si **toutes** les cases sont cochées :
- [ ] Threat model (STRIDE) rédigé et revu ; risques résiduels acceptés par écrit.
- [ ] Tests unitaires + intégration + E2E de ses parcours ; tests d'isolation/autorisation verts.
- [ ] Couverture des zones critiques ≥ seuils ; mutation sur les invariants.
- [ ] Migrations expand/contract relues ; index vérifiés (`EXPLAIN`) ; lint de schéma vert.
- [ ] OpenAPI à jour, contrats vérifiés ; clients régénérés.
- [ ] Événements documentés (schémas) ; consommateurs idempotents testés.
- [ ] i18n complète (fr/en) ; accessibilité vérifiée ; goldens clair/sombre.
- [ ] Budgets de performance respectés (mobile + API).
- [ ] Dashboards + alertes + runbooks en place ; erreurs traçables.
- [ ] Feature flag de déploiement progressif ; plan de retour arrière.
- [ ] Documentation (ARCHITECTURE/DATABASE/API/SECURITY/TESTING/CHANGELOG) et ADR mis à jour.
- [ ] Revue sécurité (audit interne étape 6 de la méthode) ; aucun secret/PII dans logs et dépôt.
- [ ] Aucune donnée fictive activable en production.
