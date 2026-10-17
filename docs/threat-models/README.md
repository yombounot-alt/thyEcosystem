# Threat models

Pour chaque zone sensible : les actifs, les menaces, la mesure en place (avec le code et le test
qui la prouvent), le risque qui reste et les écarts à traiter. Un document se révise quand le code
de sa zone change.

| Zone                                       | Document                       |
| ------------------------------------------ | ------------------------------ |
| Authentification des clients (OTP, jetons) | [auth.md](auth.md)             |
| Isolation entre entreprises (RLS, tenancy) | [tenancy.md](tenancy.md)       |
| Droits et console d'administration         | [rbac-admin.md](rbac-admin.md) |

À écrire avec les lots concernés : paiements (Money, ADR-011), fichiers envoyés par les
utilisateurs, synchronisation offline, IA (ADR-013).

## Écarts ouverts (2026-10-17)

| Écart                                                                  | Document                           |
| ---------------------------------------------------------------------- | ---------------------------------- |
| Pas de limite par IP seule sur la demande d'OTP (fraude au SMS)        | [auth.md](auth.md) A3              |
| JWT HS256 (secret partagé), à trancher                                 | [auth.md](auth.md) A6              |
| Test de fuite RLS limité au schéma `biz`                               | [tenancy.md](tenancy.md)           |
| `core.users` et `core.refresh_tokens` sans RLS                         | [tenancy.md](tenancy.md) T5        |
| Le processus API détient l'identifiant du migrateur (contourne la RLS) | [tenancy.md](tenancy.md) T3        |
| Revue du journal d'audit staff non organisée                           | [rbac-admin.md](rbac-admin.md) S7  |
| Console admin sans restriction réseau                                  | [rbac-admin.md](rbac-admin.md) S12 |
