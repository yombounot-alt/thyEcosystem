# Sécurité

## Signaler une vulnérabilité

**N'ouvrez pas d'issue publique** : ce dépôt est public. Écrivez au mainteneur, Tamba Hallo
Yombouno, par la messagerie privée de GitHub (profil `yombounot-alt`), ou utilisez
« Report a vulnerability » dans l'onglet **Security** du dépôt si l'option est activée. Indiquez :

- ce qui est touché (route, écran, fichier) ;
- les étapes pour reproduire ;
- l'impact que vous constatez.

Aucun environnement de production n'existe encore (voir [DEPLOYMENT.md](docs/DEPLOYMENT.md)) :
ne testez que sur votre propre installation locale.

## Principes appliqués dans le code

- **Le serveur décide** : un droit masqué dans l'interface est aussi refusé par l'API, et l'accès est
  refusé par défaut à toute route qui ne déclare pas son contrôle.
- **Isolation des entreprises** par RLS PostgreSQL forcée, avec un rôle applicatif qui ne peut pas
  la contourner ([ADR-004](docs/adr/0004-isolation-multi-tenant.md)).
- **Aucun secret dans le dépôt** : les valeurs de `.env.example` ne servent qu'au développement, et
  la production refuse de démarrer avec elles ([DEPLOYMENT.md](docs/DEPLOYMENT.md#configuration)).
- **Aucune donnée personnelle dans les journaux** : numéros masqués, champs sensibles retirés des
  journaux pino et des événements Sentry.
- **Mots de passe et codes** : argon2id pour les mots de passe staff ; OTP, jetons de session et
  jetons de rafraîchissement stockés hachés ; secrets TOTP chiffrés.
- **Actions sensibles du staff** : motif obligatoire, journal d'audit en ajout seul.
- **Aucun paiement simulé** : THY ne détient pas de fonds ([ADR-011](docs/adr/0011-paiements-abstraction-grand-livre-absence-de-custody.md)).

## Ce qui est vérifié en continu

`security.yml` : recherche de secrets (gitleaks), dépendances (`pnpm audit`, niveau « high »
bloquant), analyse statique (CodeQL), Trivy sur les dépendances et l'IaC, avec un SBOM. Les
invariants de sécurité ont leurs tests e2e : voir [TESTING.md](docs/TESTING.md).

## Analyse des risques

Threat models et écarts ouverts : [docs/threat-models/](docs/threat-models/README.md).
