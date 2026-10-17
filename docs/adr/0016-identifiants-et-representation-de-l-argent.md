# ADR-016 — Identifiants et représentation de l'argent

- **Statut** : Acceptée (2026-09-22, validation du blueprint)

- **Identifiants : UUIDv7** (triable par le temps → meilleure localité d'index ; **générable côté client** pour l'offline). PG 18+ fournit `uuidv7()` ; sinon génération applicative. Codes lisibles distincts (`THY-7K3F9Q`, base32) pour commandes/reçus.
- **Argent : `BIGINT` en unités mineures + `currency CHAR(3)`**, exposant ISO 4217 issu de `core.currencies` (le GNF a 0 décimale). **Jamais de `float`.** Arrondi défini par devise. Chaque ligne monétaire porte sa devise.
- **Quantités** : `NUMERIC(18,3)` (kg, litres, fractions), unité via `core.units`.
- **Temps** : `timestamptz` UTC partout ; fuseau du business pour les frontières de « jour » des rapports.
- **Téléphones** : E.164 normalisé (libphonenumber).

## Mise en œuvre (constat du 2026-10-17)

- **Écart** : les identifiants sont des UUIDv4 (`DEFAULT gen_random_uuid()` dans toutes les migrations), pas des UUIDv7.
- **Écart** : les montants du schéma `biz` (porté de thyBusiness) sont en `numeric(14,2)`, sans devise par ligne ; la devise est portée par l'entreprise (`core.businesses.currency`, `GNF` par défaut). À corriger avant le module Money et avant tout paiement réel.
- **Écart** : les dates du schéma `biz` sont en `timestamp(3)` **sans fuseau** (27 colonnes, héritage de thyBusiness) ; `core`, `ntf`, `ops` et `sub` sont en `timestamptz`. À corriger en même temps que les montants.
- Téléphones en E.164 : conformes.
