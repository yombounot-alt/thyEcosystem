# API

## Contrat

- **Référence** : [`docs/api/openapi.json`](api/openapi.json) (OpenAPI 3.0). Il est généré depuis le
  code (`pnpm --filter @thy/backend run openapi:export` après un build) et versionné, si bien qu'un
  changement d'API se voit dans la revue. La CI backend échoue si le fichier n'est pas à jour.
- En dehors de la production, l'API sert aussi le contrat sur `GET /api/v1/openapi.json`
  (`OPENAPI_ENABLED`).
- L'app mobile vérifie que chacun de ses appels existe dans ce contrat
  ([ADR-021](adr/0021-contrat-app-api-par-test-plutot-que-client-genere.md)).
- La console d'administration (`/admin/v1/*`) est **exclue** du contrat public
  ([ADR-020](adr/0020-authentification-du-staff-comptes-thy-et-totp.md)).

## Bases

| Élément    | Règle                                                                                          |
| ---------- | ---------------------------------------------------------------------------------------------- |
| Préfixe    | `/api/v1`, sauf `/health/live`, `/health/ready` et `/admin/v1/*`                               |
| Format     | JSON ; un champ non déclaré dans la requête est refusé (400)                                   |
| Dates      | ISO 8601                                                                                       |
| Téléphones | E.164 (`+224…`)                                                                                |
| Pagination | Par curseur : `?limit=&cursor=`, la réponse contient `{ items, nextCursor }` (`null` à la fin) |

## Authentification (clients)

1. `POST /auth/otp/request` avec le numéro : un code à 6 chiffres est envoyé par SMS. En
   développement, il est écrit dans les journaux, ou fixé par `DEV_FIXED_OTP`, interdit en
   production.
2. `POST /auth/otp/verify` avec le numéro et le code : la réponse contient un **jeton d'accès**
   (JWT, 15 min) et un **jeton de rafraîchissement** (opaque, 30 jours).
3. Chaque requête porte `Authorization: Bearer <jeton d'accès>`.
4. `POST /auth/refresh` échange le jeton de rafraîchissement contre une nouvelle paire. L'ancien est
   révoqué. **Réutiliser un jeton déjà échangé révoque tous les jetons de cet appareil.**
5. `POST /auth/logout` révoque la session de l'appareil.

Suspendre un compte, ou révoquer ses sessions depuis l'admin, invalide immédiatement les jetons
d'accès déjà émis (version de jeton vérifiée à chaque requête).

### Entreprise active

Les routes du module Business sont « à plat » (`/products`, `/sales`…) et visent l'**entreprise
active** du jeton. `POST /businesses/{id}/activate` vérifie que l'utilisateur en est membre et
renvoie un jeton pour cette entreprise. Les droits (par exemple `sales:create`) dépendent du rôle
dans cette entreprise.

## Erreurs

Toutes les erreurs ont la même forme :

```json
{
  "error": { "code": "ENTITLEMENT_LIMIT_REACHED", "message": "…", "details": {}, "requestId": "…" }
}
```

- `code` est **stable** : le client s'appuie dessus, jamais sur `message`, qui est en français et
  peut changer.
- `requestId` est à citer au support : il relie l'erreur aux journaux.
- Le type de contenu est `application/json`, pas `application/problem+json` (voir le
  [registre des ADR](adr/README.md#décisions-mineures)).

Codes HTTP courants : 400 (validation), 401 (jeton absent ou expiré), 403 (droit manquant,
compte suspendu, limite de l'offre atteinte), 404, 409 (conflit, par exemple un double
traitement), 429 (trop de requêtes, avec l'en-tête `Retry-After`).

## Rejouer une requête sans effet double

- **Ventes et paiements directs** : le client envoie un `clientRequestId` dans le corps. Une même
  vente renvoyée (réponse perdue, file hors ligne) est reconnue et renvoyée telle quelle, jamais
  enregistrée deux fois (contrainte `UNIQUE (business_id, client_request_id)`).
- Le kernel contient aussi un mécanisme d'en-tête `Idempotency-Key`
  (`backend/src/kernel/infra.services.ts`, table `ops.idempotency_keys`). **Aucune route ne
  l'utilise encore.**

## Limitation de débit

Les routes sensibles (demande d'OTP, vérification, connexion admin…) sont limitées par fenêtre,
avec Redis comme compteur. Une route peut cumuler plusieurs règles. La demande d'OTP est ainsi
limitée par IP + numéro (3 / 10 min) **et** par IP seule (20 / 10 min, 100 / jour), contre la
fraude au SMS ; s'y ajoutent les quotas par numéro (3 / 10 min, 10 / jour). Pour les routes les
plus sensibles, Redis indisponible entraîne un refus plutôt qu'une ouverture (`failClosed`). En
production, la limitation ne peut pas être désactivée.

## Versionnement

Le préfixe `/v1` change seulement en cas de rupture. Ajouter un champ dans une réponse ou une route
nouvelle n'est pas une rupture. Retirer ou renommer un champ en est une. **Aucun contrôle
automatique des ruptures n'existe encore** : la revue du diff de `openapi.json` en tient lieu.

## API d'administration

`/admin/v1/*`, réservée au staff : session par cookie, jeton anti-CSRF dans l'en-tête
`X-CSRF-Token`, double authentification. Ses formes de réponse sont décrites dans
`admin/src/api/types.ts` et vérifiées par `backend/test/kernel/admin.e2e-spec.ts`.
