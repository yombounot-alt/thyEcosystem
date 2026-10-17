# Threat model — droits et console d'administration

- **Périmètre** : rôles et droits dans une entreprise (RBAC) ; console du staff THY (`/admin/v1`).
- **Décisions** : [ADR-004](../adr/0004-isolation-multi-tenant.md),
  [ADR-020](../adr/0020-authentification-du-staff-comptes-thy-et-totp.md).
- **Code** : `backend/src/kernel/auth/` (gardes, permissions), `backend/src/modules/admin/`,
  `admin/`.
- **Tests** : `backend/test/kernel/rbac.e2e-spec.ts`, `team.e2e-spec.ts`,
  `admin.e2e-spec.ts` ; `admin/src/**/*.test.ts(x)`.
- **Révisé le** : 2026-10-17.

## Actifs

- Les données de toutes les entreprises et de tous les utilisateurs : la console les voit toutes.
- Les numéros de téléphone en clair.
- La capacité de suspendre un compte, de déconnecter ses appareils, de modifier l'offre d'une
  entreprise ou un feature flag.

## RBAC dans une entreprise

| #   | Menace                                         | Mesure                                                                                                                                  | Reste                          |
| --- | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| R1  | Route sans contrôle d'accès                    | `AccessGuard` global : une route qui ne déclare ni `@Public`, ni `@Authenticated`, ni `@RequirePermission` est **refusée**              | —                              |
| R2  | Élévation de rôle (un caissier se fait gérant) | Seuls les rôles qui ont le droit de gérer l'équipe changent les rôles ; le propriétaire ne peut pas être rétrogradé par un autre membre | Couvert par `team.e2e-spec.ts` |
| R3  | Droit vérifié sur la mauvaise entreprise       | Droits calculés pour l'entreprise active du jeton, émise après vérification d'appartenance                                              | —                              |

## Console d'administration

| #   | Menace                                          | Mesure                                                                                                                                          | Reste                                                                                                                    |
| --- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| S1  | Vol du mot de passe d'un membre du staff        | **TOTP obligatoire** ; argon2id ; verrouillage de 15 min après 5 échecs ; connexion limitée à 10 / 10 min par IP                                | Pas de liste de mots de passe compromis                                                                                  |
| S2  | Rejeu d'un code TOTP intercepté                 | Le dernier pas de temps utilisé est mémorisé : un code déjà utilisé est refusé                                                                  | —                                                                                                                        |
| S3  | Lecture des secrets TOTP dans la base           | Chiffrés en AES-256-GCM avec `ADMIN_TOTP_KEY` (Secret Manager) ; la production refuse la clé de développement                                   | Une fuite simultanée de la base et de la clé compromet les seconds facteurs                                              |
| S4  | Vol de session (XSS, réseau)                    | Cookie HttpOnly, `Secure`, `SameSite=Strict`, `Path=/admin/v1` ; jeton opaque haché en base ; 30 min d'inactivité, 8 h max                      | Une XSS dans la console pourrait agir pendant la session : React échappe par défaut, et aucune HTML brute n'est injectée |
| S5  | CSRF                                            | `SameSite=Strict` **et** jeton anti-CSRF (en-tête `X-CSRF-Token`) sur toute requête modifiante, renouvelé à chaque lecture de session           | —                                                                                                                        |
| S6  | Un jeton client qui ouvre l'admin, ou l'inverse | Authentifications séparées (JWT client contre cookie staff) ; testé dans les deux sens                                                          | —                                                                                                                        |
| S7  | Agent support qui abuse de son accès            | Numéros **masqués** par défaut ; afficher un numéro en clair, suspendre ou révoquer exigent un **motif** et sont **audités**                    | L'audit détecte après coup, il n'empêche pas. Revue du journal à organiser                                               |
| S8  | Traces effacées ou réécrites                    | `thy_admin_app` **et `thy_app`** n'ont que `SELECT` et `INSERT` sur `ops.audit_logs` (migration `0012` pour `thy_app`)                          | `thy_migrator` peut tout modifier : accès à réserver à peu de personnes                                                  |
| S9  | Console qui accède à plus que nécessaire        | Rôle PostgreSQL dédié, `thy_admin_app`, avec des droits **colonne par colonne** (par exemple `UPDATE (status, token_version)` sur `core.users`) | Voir [DATABASE.md](../DATABASE.md)                                                                                       |
| S10 | Création de comptes staff par la console        | Impossible : seule la CLI, avec la connexion du migrateur, crée des comptes. Aucun compte par défaut                                            | —                                                                                                                        |
| S11 | Départ d'un membre du staff                     | Suspension manuelle ([runbook](../runbooks/staff-accounts.md)), effective dès la requête suivante                                               | Pas de SSO : un départ oublié laisse le compte actif                                                                     |
| S12 | Exposition de la console sur Internet           | Routes hors contrat OpenAPI public ; `noindex`                                                                                                  | Pas de restriction réseau (IP, VPN) : à décider au déploiement                                                           |

## Écarts à traiter

1. Organiser une revue périodique du journal d'audit staff (S7), et surtout des
   `admin.user.reveal_phone`.
2. Décider d'une restriction réseau de la console en production (S12), par exemple Cloud Armor
   par IP ou un proxy d'identité.
3. Écrire une CLI de suspension et de réinitialisation TOTP, pour ne plus passer par du SQL manuel
   (S11).
4. Passer à OIDC dès qu'un fournisseur d'identité d'entreprise existe
   ([ADR-020](../adr/0020-authentification-du-staff-comptes-thy-et-totp.md)).
