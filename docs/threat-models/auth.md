# Threat model — authentification des clients

- **Périmètre** : connexion par OTP SMS, jetons d'accès et de rafraîchissement, déconnexion,
  suspension de compte. Le staff a son propre document : [rbac-admin.md](rbac-admin.md).
- **Code** : `backend/src/modules/auth/`, `backend/src/kernel/auth/`, `backend/src/kernel/security/`.
- **Tests** : `backend/test/kernel/auth.e2e-spec.ts`, `me.e2e-spec.ts`.
- **Révisé le** : 2026-10-17.

## Actifs

- La maîtrise d'un compte : y accéder, c'est voir et modifier les données de toutes les
  entreprises dont le titulaire est membre.
- Les numéros de téléphone, qui sont des données personnelles.
- Le budget SMS : chaque OTP envoyé est facturé.

## Flux

1. `POST /auth/otp/request` : un code à 6 chiffres, haché en base (`core.otp_challenges`), envoyé
   par SMS.
2. `POST /auth/otp/verify` : le code est vérifié, puis une session est émise.
3. Jeton d'accès : JWT HS256, 15 min, qui porte une version de jeton.
4. Jeton de rafraîchissement : opaque, haché en base, 30 jours, une famille par appareil.

## Menaces et mesures

| #   | Menace                                              | Mesure en place                                                                                                                       | Reste                                                                                                                                              |
| --- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| A1  | Deviner un OTP                                      | 6 chiffres, 10 min, **5 essais par code** ; vérification limitée à 10 / 10 min par IP + numéro ; comparaison à temps constant         | Faible                                                                                                                                             |
| A2  | Lire les OTP dans la base ou les journaux           | Code stocké haché (HMAC avec un poivre, `HMAC_PEPPER`) ; en dev, journalisé seulement par l'adaptateur console, avec le numéro masqué | La production refuse l'adaptateur console                                                                                                          |
| A3  | **Fraude au SMS** (faire envoyer des SMS en masse)  | Par numéro : 3 / 10 min et 10 / jour ; par IP **+ numéro** : 3 / 10 min                                                               | **Aucune limite par IP seule** : une IP peut viser des milliers de numéros. À corriger avant de brancher un vrai fournisseur SMS                   |
| A4  | Vol d'un jeton de rafraîchissement                  | Haché en base ; rotation à chaque usage ; **réutiliser un jeton déjà échangé révoque toute la famille**                               | Le jeton reste valable jusqu'à son premier usage par l'une des parties                                                                             |
| A5  | Vol d'un jeton d'accès                              | Durée de 15 min ; version de jeton vérifiée à chaque requête (suspension et révocation immédiates)                                    | Pas de lien avec l'appareil (pas de DPoP)                                                                                                          |
| A6  | Falsification de JWT                                | Signature HS256 vérifiée, algorithme imposé (`algorithms: ["HS256"]`), émetteur vérifié ; secret ≥ 32 caractères exigé en production  | Secret symétrique partagé : quiconque peut vérifier peut aussi signer. Écart avec [ADR-010](../adr/0010-authentification-construire-ou-acheter.md) |
| A7  | Compte suspendu qui continue d'agir                 | `UserStateService` (cache Redis invalidé à la suspension) bloque les écritures, même avec un jeton valide                             | —                                                                                                                                                  |
| A8  | Énumération des numéros inscrits                    | La demande d'OTP répond de la même façon que le numéro soit inscrit ou non                                                            | À revérifier quand l'inscription aura des étapes distinctes                                                                                        |
| A9  | Code OTP prévisible en production                   | `DEV_FIXED_OTP` refusé par `validateConfig()` en production                                                                           | —                                                                                                                                                  |
| A10 | Détournement d'un jeton push d'un autre utilisateur | Un appareil qui change de titulaire est rattaché au nouvel utilisateur (politique `token_holder_see`)                                 | —                                                                                                                                                  |

## Écarts à traiter

1. **A3** : ajouter une limite par IP seule et un plafond global de SMS par heure, avec alerte,
   avant tout fournisseur SMS réel.
2. **A6** : décider entre garder HS256, en le documentant dans une ADR, et passer à ES256/EdDSA
   avec JWKS, comme le prévoit ADR-010. À trancher avant qu'un second service ait à vérifier des
   jetons.
3. Écrire un test e2e qui vérifie que la demande d'OTP ne révèle pas si le numéro est inscrit (A8).
