# ADR-006 — Architecture et état côté Flutter

- **Statut** : Acceptée (2026-09-22, validation du blueprint)

| Option                                            | Avantages                                                                        | Inconvénients                                    |
| ------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Riverpod + go_router**, feature-first, packages | Testabilité, injection explicite, peu de boilerplate, très adapté à l'asynchrone | Concepts à apprendre (providers, scoping)        |
| Bloc/Cubit                                        | Très structuré, traçable, standard entreprise                                    | Plus de code ; verbeux pour des écrans simples   |
| Provider seul                                     | Simple                                                                           | Insuffisant à cette échelle                      |
| GetX                                              | Rapide au début                                                                  | Couplage fort, testabilité faible, dette assurée |

**Recommandation : Riverpod** (+ génération de code, `freezed`, `go_router` avec `StatefulShellRoute`). **Architecture en packages Melos** : un package par module + `thy_core`, `thy_design_system`, `thy_api`, `thy_sync`, `thy_l10n`, `thy_engines`. Un module est enregistré dans un `ModuleRegistry` : ajouter un module ne modifie pas le shell.
**Remise en cause si** : l'équipe maîtrise déjà Bloc et n'a pas d'expérience Riverpod → Bloc acceptable, l'architecture en packages ne change pas.

## Mise en œuvre (constat du 2026-10-17)

- Riverpod 3 + go_router ; paquets Melos `thy_core` et `thy_design_system` ; registre de modules (`mobile/app/lib/navigation/`).
- Pas de génération de code Riverpod ni de `freezed` à ce stade.
- Le paquet `thy_api` (client généré) est remplacé par un test de contrat ([ADR-021](0021-contrat-app-api-par-test-plutot-que-client-genere.md)). `thy_sync`, `thy_l10n` et `thy_engines` n'existent pas encore.
