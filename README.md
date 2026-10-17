# THY — Écosystème numérique (Super App)

THY est une application mobile unique qui réunit dix modules interconnectés (Business, Marketplace,
Services, Delivery, Immo, Jobs, Academy, Agro, Money, AI) autour d'une identité, d'une base de
données et d'une administration communes.

**Statut** : Phase 0 (Foundation), lots L0.1 à L0.12 livrés, avec des restes listés dans le
[plan](docs/plans/phase-0-foundation.md) (Widgetbook, flavors iOS, déploiement). Ce qui existe :

- le kernel : identité par OTP, entreprises et RBAC, isolation par RLS, notifications,
  abonnements et feature flags, stockage S3, observabilité ;
- le module **Business** porté de thyBusiness (catalogue, ventes y compris hors ligne, stock,
  clients et crédits, dépenses, paiements directs) ;
- l'app Flutter et la console d'administration du staff.

**Rien n'est encore déployé** : le Terraform GCP est écrit mais n'a jamais été appliqué. Les
neuf autres modules ne sont pas commencés.

## Démarrer ici

| Pour…                                    | Lire                                                                                                              |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Installer et contribuer                  | [CONTRIBUTING.md](CONTRIBUTING.md)                                                                                |
| Comprendre ce qui existe                 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)                                                                      |
| La cible, les choix, la feuille de route | [docs/blueprint/README.md](docs/blueprint/README.md)                                                              |
| Le plan de la phase en cours             | [docs/plans/phase-0-foundation.md](docs/plans/phase-0-foundation.md)                                              |
| Les décisions et leurs écarts            | [docs/adr/](docs/adr/README.md)                                                                                   |
| Base de données, API, tests, déploiement | [DATABASE](docs/DATABASE.md) · [API](docs/API.md) · [TESTING](docs/TESTING.md) · [DEPLOYMENT](docs/DEPLOYMENT.md) |
| Sécurité                                 | [SECURITY.md](SECURITY.md) · [threat models](docs/threat-models/README.md)                                        |
| Charte graphique et tokens               | [docs/brand/README.md](docs/brand/README.md)                                                                      |
| Historique                               | [CHANGELOG.md](CHANGELOG.md)                                                                                      |

## Structure du dépôt

```
backend/   API NestJS (monolithe modulaire) et migrations SQL
admin/     Console d'administration du staff (React)
mobile/    Application Flutter et ses paquets (workspace Melos)
shared/    Tokens de design, préréglages ESLint/Prettier/tsconfig
infra/     Docker local, Terraform GCP, scripts de développement
docs/      Blueprint, plans, ADR, threat models, runbooks, référence
tools/     Scripts transverses (changelog)
```

## Pile technique

Flutter · NestJS · PostgreSQL 17 + PostGIS · Redis · React (admin) · GCP visé (Cloud Run,
Cloud SQL, Memorystore, Cloud Storage). Choix et justifications : [docs/adr/](docs/adr/README.md).
