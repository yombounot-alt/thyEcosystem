# ADR-022 — Relais d'outbox sur PostgreSQL, sans BullMQ

- **Statut** : **Constatée, à valider** — choix d'implémentation fait au lot L0.8 et relevé lors de
  la documentation (2026-10-17) ; il n'a pas été soumis à validation au moment où il a été fait.
- **Amende** : [ADR-005](0005-evenements-et-taches-asynchrones.md)

## Contexte

[ADR-005](0005-evenements-et-taches-asynchrones.md) prévoit une outbox transactionnelle dans
PostgreSQL, relayée vers BullMQ (Redis), et un processus `worker` dédié
([ADR-001](0001-style-d-architecture-backend.md)). En Phase 0, les seuls consommateurs sont
internes (notifications) et le volume est faible.

## Ce qui a été construit

`backend/src/kernel/events/outbox-relay.service.ts`, exécuté dans le processus `api` :

- prise d'un événement de `ops.outbox_events` par `FOR UPDATE SKIP LOCKED` avec un bail, ce qui
  permet plusieurs instances sans double traitement ;
- backoff exponentiel et file des morts après un nombre maximal de tentatives (signalée à Sentry) ;
- consommateurs idempotents grâce à `ops.processed_events` ;
- traces OpenTelemetry du relais supprimées, pour ne pas noyer les traces des requêtes.

## Options

| Option                                     | Avantages                                                                    | Inconvénients                                                                  |
| ------------------------------------------ | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **A. Relais par scrutation de PostgreSQL** | Aucun composant de plus ; une seule source de vérité ; testé de bout en bout | Charge de scrutation sur PG ; débit limité ; ordonnanceur à écrire nous-mêmes  |
| B. Outbox → BullMQ (ADR-005)               | Retries, délais et tableaux de bord prêts à l'emploi                         | Redis devient critique (`noeviction` + AOF) ; deux systèmes à garder cohérents |

## Décision proposée

Garder **A** tant que les consommateurs sont internes et le volume faible. Le port reste le même :
passer à BullMQ, ou à un bus de messages, ne toucherait que le relais.

## Remise en cause si

Le relais retarde les requêtes de l'API, le volume dépasse quelques centaines d'événements par
seconde, ou il faut des tâches planifiées et longues : créer alors le processus `worker`
d'[ADR-001](0001-style-d-architecture-backend.md) et y déplacer le relais, avec ou sans BullMQ.
