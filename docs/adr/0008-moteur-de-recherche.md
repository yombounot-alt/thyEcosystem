# ADR-008 — Moteur de recherche

- **Statut** : Acceptée (2026-09-22, validation du blueprint) — non implémentée (Phase 3)

| Option                                                                          | Avantages                                                                                                                | Inconvénients                                                      |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| **A. PostgreSQL FTS + `pg_trgm` + PostGIS** (derrière un port `SearchProvider`) | Zéro composant en plus ; données cohérentes ; géo natif ; suffisant pour des dizaines/centaines de milliers de documents | Tolérance aux fautes/facettes moins riches ; réglages FR à soigner |
| B. Meilisearch / Typesense                                                      | Typos, facettes, relevance prête à l'emploi, simple à opérer                                                             | Nouveau composant ; synchronisation à maintenir                    |
| C. OpenSearch/Elasticsearch                                                     | Très puissant                                                                                                            | Lourd, coûteux à exploiter                                         |

**Recommandation : A** pour les phases 3 à 8, avec **table dénormalisée `search.documents` alimentée par événements** (recherche globale) et requêtes spécialisées par module (filtres riches). Migration vers B quand : > ~1 M documents, latence p95 > 300 ms, ou besoin de facettes avancées.

## Mise en œuvre (constat du 2026-10-17)

- Rien n'est encore construit ; la décision s'appliquera au lot concerné.
