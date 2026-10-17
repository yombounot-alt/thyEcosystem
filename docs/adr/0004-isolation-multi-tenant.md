# ADR-004 — Isolation multi-tenant

- **Statut** : Acceptée (2026-09-22, validation du blueprint)

| Option                                                              | Avantages                                                                                                                                                   | Inconvénients                                                                    |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| **A. Schéma partagé + `business_id` + RLS** (défense en profondeur) | Un seul schéma à migrer ; coûts minimaux ; requêtes cross-tenant possibles pour l'admin/analytics ; passe à l'échelle (partitionnement par tenant possible) | Une erreur de politique = fuite ; exige tests systématiques                      |
| B. Un schéma PG par tenant                                          | Isolation forte, restauration par tenant                                                                                                                    | Milliers de schémas = migrations ingérables, catalogue PG gonflé, pool difficile |
| C. Une base par tenant                                              | Isolation maximale                                                                                                                                          | Coût et ops prohibitifs pour des petits commerces                                |

**Recommandation : A, à quatre couches** : (1) `TenantGuard` (membership vérifié en base, jamais l'ID envoyé), (2) permissions RBAC, (3) **RLS PostgreSQL** `FORCE` avec rôle applicatif `NOBYPASSRLS`, (4) **FK composites `(business_id, id)`** + tests de fuite automatisés qui échouent si une table tenant n'a pas sa politique.
Deux autres contextes RLS : `app.user_id` (données privées utilisateur : Money, IA) et `app.staff_id` (accès admin audité).
**Remise en cause si** : un client exige un hébergement dédié (→ base par tenant pour ce client seulement, la couche applicative ne change pas).

## Mise en œuvre (constat du 2026-10-17)

- RLS `ENABLE` + `FORCE` ; rôle applicatif `thy_app` en `NOBYPASSRLS` ; contexte posé par `Db.withTenant()` (`app.user_id`, `app.business_id`).
- Clés étrangères composites `(business_id, id)` dans le schéma `biz` (migration `0004`).
- **Écart** : le test qui échoue si une table n'a pas sa RLS forcée (`backend/test/kernel/rls.e2e-spec.ts`) ne couvre que le schéma `biz`, pas `core`, `ntf` ni `sub`. Voir [le threat model tenancy](../threat-models/tenancy.md).
- Le contexte `app.staff_id` n'existe pas : l'admin passe par un rôle PostgreSQL distinct, `thy_admin_app`, avec des politiques `admin_*` explicites ([ADR-020](0020-authentification-du-staff-comptes-thy-et-totp.md)).
