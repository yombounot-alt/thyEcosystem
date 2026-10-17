# ADR-021 — Contrat app ↔ API : test de contrat plutôt que client généré

- **Statut** : Acceptée (2026-09-29, lot L0.10, commit `6621d60`)
- **Amende** : la décision mineure « Client API mobile : généré depuis OpenAPI » du
  [registre](README.md#décisions-mineures) et le paquet `thy_api` d'[ADR-006](0006-architecture-et-etat-cote-flutter.md)

## Contexte

Le contrat OpenAPI est produit à partir du code backend (`docs/api/openapi.json`), et la CI
vérifie qu'il est à jour. L'app Flutter, portée de thyBusiness, appelle l'API avec Dio et des
modèles écrits à la main. L'objectif est d'éviter qu'un appel de l'app vise un chemin ou une
méthode qui n'existe pas côté serveur.

## Options

| Option                                       | Avantages                                                            | Inconvénients                                                                                      |
| -------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| A. Client Dart généré (openapi-generator…)   | Types alignés automatiquement                                        | Réécriture de toute la couche réseau portée ; code généré volumineux ; outil de génération à figer |
| **B. Test de contrat contre `openapi.json`** | Aucune réécriture ; détecte un appel vers une route qui n'existe pas | Ne vérifie pas la forme des corps de requête et de réponse                                         |
| C. Rien                                      | —                                                                    | Une dérive n'apparaît qu'en production                                                             |

## Décision

**B.** `mobile/app/test/api_contract_test.dart` relève chaque requête de l'app et échoue si sa
méthode et son chemin n'existent pas dans `docs/api/openapi.json`.

## Conséquences

- Un renommage de route côté backend casse la CI mobile au lieu de casser l'app installée.
- Limite connue : un champ renommé dans un corps JSON n'est pas détecté. Les tests e2e backend
  et les tests de l'app sur des réponses réalistes restent la protection.
- L'admin n'est pas concerné : ses routes sont exclues du contrat public, et ses types sont
  écrits à la main dans `admin/src/api/types.ts`.

## Remise en cause si

Une dérive de forme (et non de chemin) atteint la production, ou si un nouveau module de l'app
est écrit de zéro : générer alors son client depuis OpenAPI.
