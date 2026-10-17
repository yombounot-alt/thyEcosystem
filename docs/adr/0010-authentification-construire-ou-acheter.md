# ADR-010 — Authentification : construire ou acheter

- **Statut** : Acceptée (2026-09-22, validation du blueprint), **amendée par [ADR-020](0020-authentification-du-staff-comptes-thy-et-totp.md)** pour le staff

| Option                                                                   | Avantages                                                                           | Inconvénients                                                            |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **A. Construire dans NestJS** (bibliothèques éprouvées : `jose`, Argon2) | OTP téléphone natif, contexte multi-tenant sur mesure, aucun verrouillage, coût nul | Sécurité à tester avec rigueur                                           |
| B. Keycloak / Ory                                                        | Riche (SSO, MFA)                                                                    | Lourd ; OTP téléphone via extensions ; modèle multi-tenant à adapter     |
| C. Auth0 / Clerk                                                         | Rapide                                                                              | Coût par MAU, dépendance, résidence des données, SMS OTP régional limité |
| D. Firebase Auth                                                         | Intégré à FCM                                                                       | Coût SMS, contrôle limité, fiabilité SMS locale incertaine               |

**Recommandation : A** pour les **comptes clients** ; **OIDC/SSO (ex. Google Workspace) + MFA obligatoire pour le staff** (comptes séparés). Jetons : **access JWT courts, signés asymétriquement (ES256 ou EdDSA, JWKS avec rotation)** ; **refresh tokens opaques, rotation + détection de réutilisation**, stockés hachés. Spécification : [04-identity-access.md](../blueprint/04-identity-access.md).

## Mise en œuvre (constat du 2026-10-17)

- Comptes clients : OTP par SMS (adaptateur console en dev, aucun fournisseur réel branché), refresh tokens opaques stockés hachés, rotation et révocation de toute la famille en cas de réutilisation. Durées : accès 15 min, refresh 30 jours.
- **Écart** : les jetons d'accès sont signés en **HS256** (secret partagé `JWT_SECRET`), pas en ES256/EdDSA avec JWKS et rotation de clés. À trancher avant qu'un second service ait à vérifier ces jetons.
- Staff : comptes THY + TOTP au lieu d'OIDC/SSO ([ADR-020](0020-authentification-du-staff-comptes-thy-et-totp.md)).
