# ADR-001 — Style d'architecture backend

- **Statut** : Acceptée (2026-09-22, validation du blueprint)

**Contexte.** 10 modules, une équipe de ~8 personnes, transactions inter-modules fréquentes (commande + stock + paiement + livraison), budget d'exploitation limité, besoin d'évoluer plusieurs années.

| Option                                                                     | Avantages                                                                                                                    | Inconvénients                                                                                                                                                            |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **A. Monolithe modulaire** (un dépôt, un déploiement, frontières strictes) | Transactions ACID simples ; 1 pipeline CI/CD ; refactoring peu coûteux ; ops légères ; extraction possible module par module | Discipline de frontières à outiller ; un bug de perf peut affecter tout le processus (atténué par le processus `worker` séparé)                                          |
| B. Microservices dès le départ                                             | Scalabilité indépendante ; autonomie d'équipes                                                                               | Sagas partout, observabilité distribuée, coût ops énorme, latence réseau, cohérence éventuelle sur des invariants critiques (stock, argent). Prématuré pour 8 personnes. |
| C. Serverless (fonctions)                                                  | Coût à zéro au repos                                                                                                         | Connexions DB, latence de démarrage, WebSocket difficile, débogage/test locaux pénibles, RLS + pooling compliqués                                                        |

**Recommandation : A**, avec **3 points d'entrée du même code** : `api` (HTTP + WS), `worker` (files, outbox, planificateur), `migrate` (job de migration). Un module lourd (IA, tracking de livraison) peut être déployé en `worker` dédié sans réécriture.

**Conséquences.** Règles de dépendances vérifiées en CI ([02-architecture.md](../blueprint/02-architecture.md) §5). Chaque module expose une `facade` ; schéma PG dédié par module.
**Remise en cause si** : un module dépasse durablement 30 % de la charge CPU/DB ou nécessite un cycle de déploiement indépendant → l'extraire (la facade devient une API réseau).

## Mise en œuvre (constat du 2026-10-17)

- Monolithe modulaire NestJS : un seul processus applicatif (`backend/src/main.ts`) et le migrateur (`backend/src/database/migrate-cli.ts`).
- **Écart** : pas de processus `worker` séparé. Le relais d'outbox tourne dans le processus `api` (minuterie + `FOR UPDATE SKIP LOCKED`, sûr avec plusieurs instances).
- **Écart** : les règles de dépendances entre modules ne sont pas encore vérifiées en CI (aucun `dependency-cruiser`).
