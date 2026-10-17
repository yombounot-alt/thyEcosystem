# ADR-014 — Cartographie et géocodage

- **Statut** : Acceptée (2026-09-22, validation du blueprint) — non implémentée (Phase 3)

| Option                                                       | Avantages                                          | Inconvénients                                            |
| ------------------------------------------------------------ | -------------------------------------------------- | -------------------------------------------------------- |
| Google Maps Platform                                         | Données/géocodage/itinéraires très riches          | Coût à l'usage élevé ; verrouillage                      |
| Mapbox                                                       | Personnalisable                                    | Coût, données locales variables                          |
| **MapLibre (client) + tuiles OSM hébergées + `GeoProvider`** | Coût maîtrisé, tuiles hors-ligne possibles, ouvert | Qualité des données OSM/géocodage variable selon la zone |

**Recommandation : abstraction `GeoProvider`** (tuiles, géocodage, itinéraires) + **MapLibre** ; **comparer en Phase 3** la qualité OSM vs Google sur la Guinée avant de figer. **PostGIS reste indépendant** du fournisseur (recherches par distance, zones). Adresses : **pin GPS + repère textuel** (adressage informel courant).

## Mise en œuvre (constat du 2026-10-17)

- Rien n'est encore construit ; la décision s'appliquera au lot concerné.
