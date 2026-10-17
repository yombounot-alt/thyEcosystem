# ADR-005 — Événements et tâches asynchrones

- **Statut** : Acceptée (2026-09-22, validation du blueprint), **amendée par [ADR-022](0022-relais-doutbox-sur-postgresql.md)**

| Option                                               | Avantages                                                                                              | Inconvénients                                                                                      |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| A. `EventEmitter` en mémoire seul                    | Trivial                                                                                                | Perte d'événements au crash ; non durable ; aucun rejeu                                            |
| **B. Outbox transactionnelle (PG) + BullMQ (Redis)** | Pas de double-écriture ; durable ; retries/backoff/DLQ ; simple à opérer ; port `EventBus` remplaçable | Redis devient critique (config `noeviction` + AOF) ; ordre strict non garanti hors partitionnement |
| C. Outbox + Kafka/RabbitMQ/NATS                      | Débit énorme, rétention/rejeu natifs                                                                   | Complexité d'exploitation disproportionnée à ce stade                                              |
| D. Queue Postgres (pg-boss / Graphile Worker)        | Enfilage dans la même transaction, pas de Redis pour les jobs                                          | Charge supplémentaire sur PG ; écosystème d'ordonnancement moindre                                 |

**Recommandation : B.** Règle de cohérence : **mêmes invariants ⇒ même transaction** (ex. décrémenter le stock _dans_ la transaction de vente) ; **effets inter-modules ⇒ événements** (stats, notifications, recherche, livraison). Consommateurs **idempotents** via table `ops.processed_events`.
**Remise en cause si** : > ~2 000 événements/s soutenus ou besoin de rejeu massif → basculer le relais vers NATS JetStream/Kafka (le port ne change pas).

## Mise en œuvre (constat du 2026-10-17)

- Outbox transactionnelle (`ops.outbox_events`) et consommateurs idempotents (`ops.processed_events`) : en place.
- BullMQ n'est pas utilisé : le relais lit l'outbox directement dans PostgreSQL (bail, backoff exponentiel, file des morts). Redis ne fait pas partie de la chaîne des événements.
