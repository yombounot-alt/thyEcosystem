# THY — Écosystème numérique (Super App)

THY est une application mobile unique qui réunit dix modules interconnectés (Business, Marketplace,
Services, Delivery, Immo, Jobs, Academy, Agro, Money, AI) autour d'une identité, d'une base de
données et d'une administration communes.

**Statut du projet** : Phase 0 — Foundation, en cours. Aucun module métier n'est encore implémenté.

## Démarrer ici

1. [docs/blueprint/README.md](docs/blueprint/README.md) — Master Technical Blueprint (architecture, décisions, roadmap).
2. [docs/plans/phase-0-foundation.md](docs/plans/phase-0-foundation.md) — plan détaillé de la phase en cours.
3. [docs/brand/README.md](docs/brand/README.md) — charte graphique et tokens de design.

## Structure du dépôt

Voir [docs/blueprint/13-repository-structure.md](docs/blueprint/13-repository-structure.md) pour la structure
cible complète et son raisonnement. Les dossiers sont créés au fil des phases, pas par anticipation.

```
backend/   API + worker NestJS (monolithe modulaire)
admin/     Console d'administration (React)
mobile/    Application Flutter (workspace Melos)
shared/    Contrats API, tokens de design, catalogue de permissions
infra/     Infrastructure as Code (Terraform, GCP) + environnement Docker local
docs/      Blueprint, plans de phase, ADR, runbooks, charte de marque
tools/     Scripts transverses du dépôt
```

## Pile technique (résumé)

Flutter · NestJS · PostgreSQL + PostGIS · Redis · GCP (Cloud Run, Cloud SQL, Memorystore,
Cloud Storage) · Firebase Cloud Messaging · React (admin). Détail et justification de chaque choix :
[docs/blueprint/01-decisions.md](docs/blueprint/01-decisions.md).

## Contribuer

Voir `CONTRIBUTING.md` (à venir, lot L0.12).
