# ADR-013 — LLM : fournisseur et orchestration

- **Statut** : Acceptée (2026-09-22, validation du blueprint) — non implémentée (Phase 2)

| Option                                                                                   | Avantages                                                                                         | Inconvénients                                               |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| A. Un seul fournisseur en dur                                                            | Simple                                                                                            | Verrouillage, panne = IA indisponible                       |
| **B. Port `LlmProvider` (chat, stream, vision, embeddings) + routage par tâche + repli** | Changer de fournisseur = adaptateur ; coûts maîtrisés (petit modèle pour le routage) ; résilience | Un peu plus de conception                                   |
| C. Modèle open-weights auto-hébergé                                                      | Souveraineté, coût marginal à grande échelle                                                      | GPU, ops, qualité FR/vision/tool-calling à prouver          |
| D. Framework d'agents généraliste (LangChain, etc.)                                      | Rapide pour prototyper                                                                            | Abstractions opaques, contrôle d'autorisation fin difficile |

**Recommandation : B**, orchestration **écrite maison et minimale** (pipeline de [07-ai.md](../blueprint/07-ai.md)) — l'autorisation par outil est le cœur du système et ne doit pas être déléguée à un framework. **Choix du fournisseur par évaluation** sur un jeu de tests THY (français, appel d'outils, vision, latence, coût), pas par défaut. Vérifier contractuellement : non-rétention/non-entraînement, résidence, DPA.

## Mise en œuvre (constat du 2026-10-17)

- Rien n'est encore construit ; la décision s'appliquera au lot concerné.
