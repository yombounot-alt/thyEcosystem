# 09 — Architecture de l'administration centrale

Couvre le point 18.

---

## 1. Principes

1. **Console interne à haut risque** : c'est la surface d'attaque la plus précieuse. Elle est isolée des comptes clients.
2. **Moindre privilège + traçabilité totale** : toute action modifiante est **auditée** (qui, quoi, quand, avant/après, motif).
3. **Rien n'est éditable « à la main » dans les données financières** : pas de changement manuel de statut de paiement ; corrections par **écritures compensatoires** validées.
4. **Construite progressivement** : chaque phase livre les écrans de son module (l'admin n'est pas un chantier séparé de 20 sections).

## 2. Architecture

| Élément           | Choix                                                                                                                                                                       |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Front             | **React + Vite + TypeScript**, TanStack Query/Table/Router, composants accessibles, tokens partagés avec Flutter                                                            |
| API               | Même backend sous `/admin/v1/*` (hôte séparé conseillé), **guards distincts**, schémas de validation propres                                                                |
| Identité          | **`staff_users` séparé**, SSO OIDC + **MFA obligatoire** (TOTP/WebAuthn), sessions courtes, cookie `HttpOnly; Secure; SameSite=Strict` + **CSRF**, liste d'IP optionnelle   |
| Autorisation      | RBAC **plateforme** (permissions `admin:*`) ; par section ; **jamais** déduite de rôles clients                                                                             |
| Accès aux données | Rôle DB `thy_admin_app` ; accès aux données d'un tenant **motivé, limité dans le temps, audité** (« support access session ») ; **pas d'usurpation de session utilisateur** |
| Données sensibles | Masquage par défaut (téléphones, e-mails, documents) ; **révélation = action auditée** ; exports contrôlés et journalisés                                                   |
| Hébergement       | SPA statique derrière CDN ; API admin protégée par WAF                                                                                                                      |

## 3. Rôles plateforme

| Rôle            | Portée                                                                                |
| --------------- | ------------------------------------------------------------------------------------- |
| SUPER_ADMIN     | Tout, y compris gestion du staff ; **usage exceptionnel**, alertes à chaque connexion |
| ADMIN           | Configuration, plans, catalogues, flags                                               |
| MODERATOR       | Files de modération, contenu, signalements                                            |
| VERIFIER        | Files de vérification (KYC/entreprise/pro/propriétaire)                               |
| SUPPORT_AGENT   | Tickets, recherche utilisateur, révocation de sessions, litiges (avec limites)        |
| FINANCE         | Paiements, réconciliation, remboursements, versements                                 |
| DATA_ANALYST    | Données **agrégées/pseudonymisées** uniquement                                        |
| CONTENT_MANAGER | Contenu Academy, catégories, gabarits de notification                                 |

**Double validation (4-yeux)** obligatoire pour : bannissement de compte/business, versement au-dessus d'un seuil, remboursement exceptionnel, changement de rôle staff, export massif de données personnelles, modification de plan tarifaire actif.

## 4. Sections (cible) et phase de livraison

| Section du brief    | Contenu principal                                                                                                                              | Phase               |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| **Dashboard**       | Indicateurs santé (inscriptions, actifs, commandes, paiements, files en attente, erreurs)                                                      | 0 (base) → évolue   |
| **Users**           | Recherche, profil, personas, sessions/appareils, restrictions, historique                                                                      | 0                   |
| **Businesses**      | Tenants, statut, abonnement, membres, vérification                                                                                             | 1                   |
| **System settings** | Flags, plans/entitlements, pays/devises/unités, catégories, gabarits de notification, versions minimales de l'app, documents légaux versionnés | 0–1                 |
| **Audit**           | Recherche/filtre du journal, export                                                                                                            | 0                   |
| **Subscriptions**   | Plans, abonnements, overrides, factures                                                                                                        | 1                   |
| **Payments**        | Paiements, tentatives, webhooks, réconciliation, remboursements, versements                                                                    | 1 (abonnements) → 3 |
| **AI**              | Usage, coûts, quotas, taux d'échec, évaluations                                                                                                | 2                   |
| **Marketplace**     | Boutiques, listings, commandes, litiges                                                                                                        | 3                   |
| **Moderation**      | File unifiée, cases, décisions, recours                                                                                                        | 3                   |
| **Verification**    | File de revue, visionneuse de pièces (URL signées), décisions                                                                                  | 3                   |
| **Support**         | Tickets, litiges, macros                                                                                                                       | 3                   |
| **Delivery**        | Livreurs, missions, tarifs, incidents, remises de caisse COD                                                                                   | 4                   |
| **Services**        | Prestataires, devis/réservations, litiges                                                                                                      | 5                   |
| **Immo**            | Annonces, visites, vérifications, signalements                                                                                                 | 6                   |
| **Jobs**            | Offres, employeurs, signalements                                                                                                               | 7                   |
| **Agro**            | Producteurs, offres, commandes, transport                                                                                                      | 8                   |
| **Money**           | Statistiques agrégées uniquement (données perso non consultables)                                                                              | 9                   |
| **Academy**         | Cours, publication, quiz, statistiques                                                                                                         | 10                  |
| **Reports**         | Rapports transversaux (Metabase intégré ou pages dédiées)                                                                                      | 11                  |

## 5. Comportements transverses

- **Tableaux** serveur-pilotés : pagination par curseur, filtres persistés, export **audité**.
- **File de travail** (moderation/verification/support/paiements) avec assignation, SLA, priorité, verrou d'édition (un item traité par une personne à la fois).
- **Historique** visible sur chaque entité (« qui a fait quoi »).
- **Mode lecture seule** par défaut sur les entités sensibles ; action modifiante = confirmation + motif obligatoire.
- **Alertes internes** : DLQ non vide, divergence de réconciliation, pics de signalements, coûts IA/SMS.
- **Accessibilité et i18n** : mêmes exigences que l'app mobile (fr/en).

## 6. Sécurité spécifique

Protection **brute-force** et verrouillage ; alertes de connexion staff inhabituelle ; **revue périodique des accès** (trimestrielle) ; désactivation immédiate du compte staff à la sortie ; journal d'audit **inaltérable** (append-only, permissions restreintes, éventuellement chaînage de hachage) ; tests d'autorisation dédiés (matrice rôle × route générée).
