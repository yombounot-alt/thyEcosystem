# ADR-009 — Temps réel

- **Statut** : Acceptée (2026-09-22, validation du blueprint) — non implémentée

| Option                                               | Avantages                                                                       | Inconvénients                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| **A. Socket.IO (NestJS Gateway) + adaptateur Redis** | Reconnexion, heartbeats, rooms, accusés natifs — précieux sur réseaux instables | Protocole propriétaire au-dessus de WS                         |
| B. WebSocket natif (`ws`)                            | Léger, standard                                                                 | Reconnexion/rooms/ack à écrire                                 |
| C. SSE                                               | Simple, unidirectionnel, traverse bien les proxys                               | Pas de bidirectionnel                                          |
| D. Firebase RTDB/Firestore                           | Rapide                                                                          | Second système de vérité, verrouillage, autorisation dupliquée |

**Recommandation : A.** Le temps réel n'est qu'une **optimisation** : toute information essentielle reste récupérable par REST et par push FCM. SSE utilisé pour le streaming des réponses IA.

## Mise en œuvre (constat du 2026-10-17)

- Rien n'est encore construit ; la décision s'appliquera au lot concerné.
