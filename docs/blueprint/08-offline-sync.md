# 08 — Architecture offline et synchronisation

Couvre le point 10. **Principe : synchroniser des intentions métier (commandes), pas copier de l'état.** Une vente faite hors-ligne est un **fait du monde réel** : le serveur ne peut pas la « refuser », seulement l'enregistrer et signaler les incohérences.

---

## 1. Périmètre offline par module

| Module                                      | Lecture hors-ligne                                                                   | Écriture hors-ligne                                                                                        | Notes                                                                               |
| ------------------------------------------- | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| **Business**                                | Catalogue, catégories, contacts, niveaux de stock, ventes récentes, rapports du jour | **Ventes, retours, dépenses, encaissements de crédits, contacts, mouvements de stock**, sessions de caisse | Priorité n°1                                                                        |
| Money                                       | Comptes, budgets, transactions                                                       | Saisie de transactions (append-only)                                                                       | Données perso synchronisées                                                         |
| Academy                                     | Cours/leçons **téléchargés**                                                         | Progression, tentatives de quiz                                                                            | Vidéos : téléchargement explicite                                                   |
| Marketplace / Services / Immo / Jobs / Agro | Cache de consultation (stale-while-revalidate)                                       | **Brouillons** (annonces, candidatures, demandes)                                                          | Pas de commande/paiement hors-ligne                                                 |
| Delivery (livreur)                          | Missions assignées                                                                   | Événements de statut (`PICKED_UP`, `DELIVERED`) avec preuve                                                | Sync dès reconnexion                                                                |
| Paiements PSP                               | —                                                                                    | **Aucune** (nécessite le réseau)                                                                           | Un règlement mobile money externe au POS est **saisi comme référence non vérifiée** |

## 2. Composants côté mobile

```
LOCAL DATABASE (Drift/SQLite + SQLCipher)
  ├─ tables miroir (lecture)     products, contacts, stock_levels, sales_recent, …
  ├─ sync_queue (commandes)      op_id · type · payload · aggregate_id · base_version · device_created_at · statut
  ├─ sync_state                  curseurs par entité, dernière synchro, horloge serveur estimée
  └─ conflict_inbox              conflits à arbitrer par l'utilisateur
SYNC ENGINE
  ├─ Push  : file ordonnée par agrégat → POST /sync/push (lots) → résultat par opération
  ├─ Pull  : delta par curseur → upsert/tombstone → notifications UI
  └─ Déclencheurs : retour réseau · ouverture app · après chaque commande · tâche de fond (WorkManager / BGTask)
```

**Structure d'une commande**

```json
{
  "op_id": "018f…(uuidv7 client)",
  "type": "sales.create",
  "aggregate_id": "018f…(uuidv7 client)",
  "base_version": null,
  "device_id": "…",
  "device_created_at": "2026-09-21T09:12:03Z",
  "payload": { "location_id": "…", "items": [ … ], "payments": [ … ], "customer_id": null }
}
```

Les **identifiants sont générés côté client** (UUIDv7) ⇒ aucune collision, idempotence naturelle, relations locales valides avant la synchro.

## 3. Protocole

### 3.1 Push

`POST /businesses/:id/sync/push` avec `Idempotency-Key` par lot. Chaque commande est traitée **dans sa propre transaction** (une commande en échec ne bloque pas les autres, hors dépendance d'agrégat).

Résultat par opération :

| Statut               | Signification                                                                        | Action client                                                  |
| -------------------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| `APPLIED`            | Appliquée                                                                            | Retirer de la file                                             |
| `DUPLICATE`          | `op_id` déjà traité (rejeu)                                                          | Retirer, réutiliser le résultat stocké                         |
| `APPLIED_WITH_FLAGS` | Appliquée **et** incohérence détectée (stock négatif, prix changé, produit archivé…) | Retirer + notification au responsable (`needs_review`)         |
| `CONFLICT`           | Entité modifiable en conflit (voir §4)                                               | Placer dans `conflict_inbox`                                   |
| `REJECTED`           | Refus déterministe (permission retirée, entitlement, validation)                     | Conserver en erreur visible avec **raison** et action possible |
| `RETRY`              | Erreur transitoire                                                                   | Backoff exponentiel                                            |

Le serveur **revalide au moment de la synchro** : permissions et entitlements actuels, existence des références, format. Il enregistre `device_created_at` (heure métier) **et** `recorded_at` (heure serveur, vérité d'ordre).

### 3.2 Pull (delta)

`GET /businesses/:id/sync/pull?entity=products&cursor=…` → `{ upserts[], tombstones[], next_cursor }`.

- Curseur = **`(updated_at, id)` en keyset** avec **fenêtre de recouvrement** (relecture des N dernières minutes, application **idempotente par `version`**) : évite de manquer des lignes validées après un `updated_at` plus récent (transactions concurrentes).
- **Tombstones** conservés ≥ 90 jours ; un client absent plus longtemps fait une **resynchronisation complète**.
- Pagination bornée, compression, **opt-in par entité** ; **première synchro** priorisée (catalogue d'abord, historique ensuite).

## 4. Résolution des conflits par nature de donnée

| Nature                            | Exemples                                                                      | Règle                                                                                                                                                                                                                                                                             |
| --------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Faits immuables** (append-only) | ventes, mouvements de stock, dépenses, encaissements, événements de livraison | **Aucun conflit d'écriture** (IDs client, idempotence). Les **incohérences sémantiques** (stock négatif, prix modifié entre-temps) sont **acceptées et signalées** (`needs_review`), jamais rejetées : la marchandise est déjà partie.                                            |
| **Compteurs dérivés**             | niveau de stock                                                               | Le client **n'envoie jamais** une quantité absolue : il envoie des **mouvements** ; le serveur calcule.                                                                                                                                                                           |
| **Données maîtres éditables**     | produit, contact, paramètres                                                  | **Verrou optimiste** (`base_version`). Champs **non chevauchants** ⇒ fusion automatique (3-way par champ). Champs **chevauchants** ⇒ `CONFLICT` → **Boîte de conflits** : l'utilisateur choisit (version locale / serveur / fusion manuelle). **Jamais d'écrasement silencieux.** |
| **Suppressions**                  | archiver un produit                                                           | Soft delete ; un produit archivé encore vendu hors-ligne ⇒ vente acceptée + drapeau.                                                                                                                                                                                              |
| **Numérotation de documents**     | n° de reçu/facture                                                            | **Série par appareil et par lieu** (`A-0001`, préfixe d'appareil) ⇒ pas de collision. Si la loi locale exige une séquence continue, numéro **officiel attribué à la synchro** et numéro provisoire hors-ligne (**à valider juridiquement**).                                      |

## 5. Horloge, ordre, robustesse

- **Ne jamais faire confiance à l'heure de l'appareil pour l'ordre** ; le serveur envoie son heure (`Date`/champ) → estimation du décalage ; décalage > seuil ⇒ avertissement à l'utilisateur et drapeau sur les opérations.
- **Ordre** : commandes ordonnées **par agrégat** ; entre agrégats indépendants, pas de dépendance.
- **Reprise sur incident** : la file est **durable** (SQLite, transactions) ; crash/kill/coupure en plein envoi ⇒ rejeu sûr grâce à l'idempotence.
- **Fenêtre journalière** : le « jour métier » d'une vente suit le **fuseau du business** et `occurred_at` ; une vente tardive **recalcule** l'agrégat du jour concerné (`biz.daily_aggregates`).
- **Coûts** : le `unit_cost_minor` est figé à la synchro à partir du CMP courant si le client n'en avait pas ; signalé si l'écart est significatif.

## 6. Sécurité offline

| Sujet                          | Décision                                                                                                                                                                                                                           |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Chiffrement local              | SQLCipher ; clé en Keystore/Keychain, liée à l'appareil                                                                                                                                                                            |
| Verrouillage                   | PIN/biométrie locale après inactivité ; caisse verrouillable par utilisateur                                                                                                                                                       |
| Durée hors-ligne maximale      | Au-delà de **N jours** sans validation serveur (configurable) : retour en ligne exigé                                                                                                                                              |
| Permissions en cache           | Rôles/permissions mis en cache avec date de validité ; **opérations à risque** (remboursement élevé, suppression, export) exigent le réseau ou un seuil d'autorisation locale                                                      |
| Entitlements                   | Cache avec **délai de grâce** (pas de blocage de caisse en pleine journée)                                                                                                                                                         |
| Déconnexion / session révoquée | Indicateur reçu à la reconnexion ⇒ **synchronisation finale** des opérations en attente puis **effacement** de la base locale (ou effacement immédiat si l'utilisateur le demande, avec avertissement des opérations non envoyées) |
| Appareil perdu                 | Révocation de session côté serveur ; les opérations non synchronisées restent dans la base **chiffrée** de l'appareil                                                                                                              |

## 7. Expérience utilisateur

- **Indicateur permanent** : en ligne / hors-ligne / synchro en cours / **N opérations en attente** / erreurs.
- Chaque vente hors-ligne porte un statut visible (« En attente d'envoi », « Synchronisée », « À vérifier »).
- **Écran « Synchronisation »** : détail des opérations, erreurs avec raison humaine, relance manuelle.
- **Boîte de conflits** : comparaison côte à côte, une décision à la fois, historique conservé.
- Les fonctions indisponibles hors-ligne sont **désactivées avec explication**, pas silencieusement.

## 8. Tests spécifiques (voir [10](10-testing.md))

- **Simulation déterministe** de la sync : ordre aléatoire, doublons, coupures en plein lot, horloges décalées, deux appareils modifiant le même produit ⇒ **convergence** et **aucune perte** (tests par propriétés).
- Tests d'intégration Flutter avec **réseau simulé** (coupure, latence, perte).
- Test de **charge de resynchronisation** (première synchro d'un gros catalogue sur appareil modeste).

## 9. Décision de spike (début Phase 1)

Évaluer PowerSync/ElectricSQL **uniquement pour le pull** (ADR-007) : gain de code vs dépendance, compatibilité **RLS multi-tenant**, coût, contrôle des jetons. Le **push par commandes** reste maison dans tous les cas.
