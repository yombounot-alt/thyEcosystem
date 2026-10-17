# ADR-020 — Authentification du staff : comptes THY et TOTP

- **Statut** : Acceptée (2026-09-29, choix de l'utilisateur ; livrée au lot L0.11, commit `cb3c58e`)
- **Amende** : [ADR-010](0010-authentification-construire-ou-acheter.md) (partie staff) et
  [ADR-004](0004-isolation-multi-tenant.md) (contexte `app.staff_id`)

## Contexte

[ADR-010](0010-authentification-construire-ou-acheter.md) prévoyait OIDC/SSO (par exemple
Google Workspace) avec MFA obligatoire pour le staff. Au moment de construire l'admin (L0.11),
THY n'a aucun fournisseur d'identité d'entreprise. Attendre en bloquerait le lot.

## Options

| Option                                      | Avantages                                                                   | Inconvénients                                                                  |
| ------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **A. Comptes staff THY + TOTP obligatoire** | Aucune dépendance externe ; MFA forte et standard ; tout reste dans la base | Mots de passe et secrets TOTP à protéger nous-mêmes ; pas de départ centralisé |
| B. OIDC/SSO (Google Workspace…)             | Départ d'un employé centralisé ; MFA gérée par le fournisseur               | Exige un tenant d'entreprise qui n'existe pas encore                           |
| C. Lien magique par e-mail                  | Pas de mot de passe                                                         | Sécurité réduite à celle de la boîte mail ; pas de second facteur              |

## Décision

**A.**

- Comptes dans `core.staff_users`, créés uniquement par la CLI `staff:create` avec la connexion
  du migrateur. Aucun compte par défaut ; le mot de passe est généré et affiché une seule fois.
- Mot de passe argon2id. Comparaison factice si l'e-mail est inconnu, pour ne pas révéler les
  comptes existants.
- TOTP RFC 6238 obligatoire dès la première connexion, avec une fenêtre de ±30 s. Un code déjà
  utilisé est refusé (dernier pas mémorisé). Le secret est chiffré au repos en AES-256-GCM
  (`ADMIN_TOTP_KEY`).
- Session opaque dans le cookie `thy_admin_session` (HttpOnly, `SameSite=Strict`,
  `Path=/admin/v1`, `Secure` en production), stockée hachée dans `core.staff_sessions`.
  Expiration après 30 min d'inactivité et au plus tard après 8 h.
- Jeton anti-CSRF exigé sur toute requête qui modifie quelque chose (en-tête `X-CSRF-Token`),
  renouvelé à chaque lecture de la session.
- Verrouillage de 15 min après 5 échecs (mot de passe ou code).
- Rôles plateforme SUPER_ADMIN / ADMIN / SUPPORT_AGENT et droits `admin:*`
  (migration `0010_admin.sql`). Toute action qui modifie quelque chose exige un motif et est
  journalisée avec `actor_type = 'staff'`.
- Accès aux données par un rôle PostgreSQL dédié, `thy_admin_app`, avec des droits et des
  politiques RLS `admin_*` explicites. Il remplace le contexte `app.staff_id` prévu par
  [ADR-004](0004-isolation-multi-tenant.md).
- Routes servies sous `/admin/v1/*`, hors du préfixe `api/v1` et hors du contrat OpenAPI public.

## Conséquences

- La production refuse de démarrer avec la clé TOTP de développement, avec un cookie non
  `Secure`, ou si l'URL de la base admin est celle de l'application ou du migrateur.
- Le cookie impose que la console soit servie **sur la même origine** que `/admin/v1` : règle du
  load balancer à ajouter au moment du `terraform apply`.
- Le départ d'un membre du staff se gère à la main (désactivation du compte).
- Tests : `backend/test/kernel/admin.e2e-spec.ts` et `admin/src/**/*.test.ts(x)`. Modèle de
  menaces : [rbac-admin.md](../threat-models/rbac-admin.md).

## Remise en cause si

THY dispose d'un tenant Google Workspace ou équivalent : passer à OIDC pour l'identification, en
gardant les rôles, le journal d'audit et le rôle PostgreSQL décrits ici.
