# Déploiement

> **État au 2026-10-17 : rien n'est déployé.** Le Terraform de staging et le squelette de
> production sont écrits et validés (`terraform fmt` et `validate` en CI), mais **n'ont jamais été
> appliqués** : aucun projet GCP n'existe encore. Le premier `apply` peut révéler des erreurs que
> `validate` ne voit pas.

Décision : [ADR-012](adr/0012-hebergement-cloud-et-region.md) (GCP, Cloud Run, `europe-west1`).
La procédure pas à pas est dans [`infra/terraform/README.md`](../infra/terraform/README.md) ; ce
document en donne la vue d'ensemble et les points d'attention.

## Cible

| Composant         | Service GCP                                     | Module Terraform                                             |
| ----------------- | ----------------------------------------------- | ------------------------------------------------------------ |
| API               | Cloud Run (`api`)                               | `cloud-run-service`                                          |
| Migrations        | Cloud Run Job (`migrate`), avant chaque version | `cloud-run-job`                                              |
| Base              | Cloud SQL PostgreSQL 17 (PostGIS)               | `cloud-sql`                                                  |
| Cache, limitation | Memorystore Redis                               | `redis`                                                      |
| Fichiers          | Cloud Storage (API compatible S3, clé HMAC)     | `storage`                                                    |
| Secrets           | Secret Manager                                  | `secret-manager`                                             |
| Images            | Artifact Registry                               | `artifact-registry`                                          |
| Réseau            | VPC privé + connecteur d'accès                  | `network`                                                    |
| Alertes           | Cloud Monitoring                                | `monitoring`                                                 |
| CDN + WAF         | Cloud CDN + Cloud Armor                         | `edge-cdn-armor` (écrit, non instancié : il faut un domaine) |

Staging et production sont deux **projets GCP distincts**.

## Ordre d'un premier déploiement

Détail et commandes : [`infra/terraform/README.md`](../infra/terraform/README.md#premier-déploiement-dans-lordre).

1. `bootstrap/` : bucket d'état, compte de service Terraform, fédération d'identité GitHub.
2. Première passe : tout sauf Cloud Run (le registre d'images doit exister avant l'image).
3. Construire et pousser l'image depuis la racine : `docker build -f backend/Dockerfile .`
4. Seconde passe : job `migrate`, service `api`, alertes.
5. Créer les rôles `thy_app`, `thy_readonly` et `thy_admin_app` avec les mots de passe générés par
   Terraform (`terraform output -raw bootstrap_roles_sql`).
6. Exécuter le job `migrate`, puis vérifier `GET /health/ready`.
7. Créer le premier super-administrateur : [runbook](runbooks/staff-accounts.md).

## Configuration

Toutes les variables sont listées, avec leur valeur de développement, dans
[`backend/.env.example`](../backend/.env.example). Les secrets (URL des bases, `JWT_SECRET`,
`HMAC_PEPPER`, clé HMAC du bucket, `ADMIN_TOTP_KEY`…) sont générés par Terraform et injectés depuis
Secret Manager ; aucun n'est écrit dans le dépôt.

Avec `NODE_ENV=production`, **l'API refuse de démarrer** dans chacun de ces cas
(`validateConfig()`, `backend/src/kernel/config/config.ts`) :

- `JWT_SECRET` ou `HMAC_PEPPER` absent ou trop court ;
- `DEV_FIXED_OTP` défini ;
- SMS ou push en mode « console » (aucune livraison réelle) ;
- stockage sur disque local, ou `S3_ENDPOINT` sans https ;
- limitation de débit désactivée ;
- `ADMIN_TOTP_KEY` absente (la clé de développement est interdite) ;
- `ADMIN_DATABASE_URL` qui n'utilise pas le rôle `thy_admin_app` ;
- cookie admin sans `Secure`.
- `MIGRATOR_DATABASE_URL` fourni au service API : cette connexion contourne la RLS et reste
  réservée au job `migrate`.

**Conséquence aujourd'hui** : aucun fournisseur SMS ni push réel n'est branché. La production ne
peut donc pas démarrer, et c'est voulu. Le staging tourne en `NODE_ENV=development` pour cette
raison.

## Points d'attention

- **Console d'administration** : elle doit être servie sur **la même origine** que `/admin/v1`,
  car le cookie de session est `SameSite=Strict` avec `Path=/admin/v1`. Il faut une règle de routage
  dans le load balancer (fichiers statiques de `admin/dist` d'un côté, `/admin/v1/*` vers l'API de
  l'autre). Ni cette règle ni l'hébergement des fichiers statiques ne sont encore écrits.
- **Migrations** : forward-only. Une migration déjà appliquée ne se modifie jamais : le migrateur
  refuse de démarrer si une somme de contrôle a changé. Procédure : [runbook](runbooks/migrations.md).
- **Changer de région** une fois Cloud SQL peuplé est une migration de données, pas un simple
  `apply`.
- **Coût** : Cloud SQL, Memorystore et le connecteur VPC facturent en continu. `terraform destroy`
  sur staging quand il ne sert pas.
- **Limites connues**, détaillées dans le README Terraform : Redis sans TLS, egress non restreint,
  un seul compte de service pour `api` et `migrate`, rôles Terraform larges.

## Pas encore écrit

- `cd-staging.yml` (déploiement automatique depuis `main`) : à faire après un premier `apply`
  manuel réussi.
- Hébergement de la console d'administration (voir ci-dessus).
- Publication de l'app mobile : identifiant d'app provisoire (`com.thyecosystem.app`), signature de
  production et flavors iOS non faits.
