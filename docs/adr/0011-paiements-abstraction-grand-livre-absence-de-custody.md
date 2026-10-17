# ADR-011 — Paiements : abstraction, grand livre, absence de custody

- **Statut** : Acceptée (2026-09-22, validation du blueprint) — non implémentée

| Option                                                                                                                  | Avantages                                                                                                                             | Inconvénients                                                                             |
| ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| A. Intégration directe par fonctionnalité                                                                               | Rapide                                                                                                                                | Dépendance à un prestataire, doublons, impossible à auditer                               |
| **B. `PaymentProvider` abstrait + machine d'états interne + grand livre à double entrée ; THY ne détient pas de fonds** | Multi-fournisseurs, audit complet, réconciliation, remboursements propres ; pas de statut d'établissement de paiement requis a priori | Plus de conception initiale ; dépend des capacités (split/escrow) du fournisseur          |
| C. Portefeuille THY custodial                                                                                           | Contrôle total des flux                                                                                                               | **Réglementation monnaie électronique / établissement de paiement** ; risque légal majeur |

**Recommandation : B.** Le grand livre enregistre des **obligations** (dû au vendeur, commission THY), pas une garde de fonds. Le séquestre éventuel (Marketplace/Services/Agro) passe par les fonctions du PSP agréé — **à valider juridiquement**. Détails : [06-platform-engines.md](../blueprint/06-platform-engines.md) §1.
**Point d'attention.** Les règles des stores (Apple/Google) sur les **biens numériques** (abonnements, cours Academy) peuvent imposer leur facturation intégrée — **à vérifier avant la Phase 10** (risque R9).

## Mise en œuvre (constat du 2026-10-17)

- Aucun paiement réel ni simulé. Le module Business enregistre des encaissements déclarés par le commerçant, sans prestataire.
