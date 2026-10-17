# ADR-007 — Base locale mobile et synchronisation offline

- **Statut** : Acceptée (2026-09-22, validation du blueprint) — non implémentée (Phase 1)

**Base locale**

| Option                     | Avantages                                                                                           | Inconvénients                                                               |
| -------------------------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **Drift (SQLite)**         | Relationnel (ventes, stock, contacts), migrations, requêtes typées, SQLCipher possible, très stable | Génération de code                                                          |
| Isar                       | API simple                                                                                          | Incertitude de maintenance ; modèle non relationnel                         |
| Hive / ObjectBox / sqflite | Simplicité / performance / bas niveau                                                               | Non relationnel (Hive), licence/écosystème (ObjectBox), verbosité (sqflite) |

**Synchronisation**

| Option                                                   | Avantages                                                                                   | Inconvénients                                                                         |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **A. Journal de commandes maison + delta-pull**          | Sémantique métier (une vente est un fait) ; contrôle total des conflits ; pas de dépendance | À écrire et tester rigoureusement                                                     |
| B. PowerSync / ElectricSQL (sync d'état Postgres↔SQLite) | Accélère la **lecture** (catalogue, contacts) ; moins de code de pull                       | Ne résout pas la sémantique d'écriture ; dépendance produit ; opérations à comprendre |
| C. Firebase Firestore offline                            | Rapide à prototyper                                                                         | Verrouillage, modèle non relationnel, coûts, multi-tenant/RLS impossibles             |
| D. CRDT (Automerge/Yjs)                                  | Fusion automatique                                                                          | Inadapté aux invariants comptables (stock, argent)                                    |

**Recommandation : Drift chiffré + A pour l'écriture** ; **spike d'une semaine en début de Phase 1** pour décider si B remplace _seulement le pull_ (lecture). Détails : [08-offline-sync.md](../blueprint/08-offline-sync.md).
**Remise en cause si** : le spike montre un gain > 3 semaines de B sur le pull sans compromis de sécurité multi-tenant.

## Mise en œuvre (constat du 2026-10-17)

- Pas de Drift ni de base locale relationnelle.
- Le portage Business a apporté une **file de ventes hors ligne**, forme limitée du journal de commandes : `mobile/app/lib/features/sales/offline/`. Elle est stockée en JSON dans SharedPreferences (`LocalStore` de `thy_core`), **non chiffrée**, et envoyée dans l'ordre avec le même `client_request_id` à chaque tentative, ce qui évite les doublons (`UNIQUE (business_id, client_request_id)` côté serveur). Le serveur marque ces ventes `biz.sales.is_offline` (migration `0007`).
- **Écart** avec cette ADR : stockage non chiffré, et rien d'autre que les ventes n'est disponible hors ligne. Le spike prévu en Phase 1 reste à faire.
