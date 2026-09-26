# Infrastructure GCP (Terraform) — L0.4

Provisionne un environnement THY sur Google Cloud : réseau privé, Cloud SQL (PostgreSQL 17),
Memorystore (Redis), Cloud Storage, Secret Manager, Artifact Registry, Cloud Run (`api` + job
`migrate`) et l'observabilité de base. Décisions : [ADR-012](../../docs/blueprint/01-decisions.md)
(GCP, région `europe-west1` par défaut faute de mesure de latence).

> **État (2026-09-26)** : le code est écrit et **validé localement** (`terraform fmt -check` et
> `terraform validate` verts sur `bootstrap/`, `environments/staging`, `environments/production` et
> chaque module). Il n'a **jamais été appliqué** : aucun projet GCP n'existe encore (c'est le
> prérequis explicite de L0.4) et aucun accès GCP n'est disponible depuis l'environnement de
> développement. Le premier `apply` réel peut donc révéler des erreurs d'API que `validate` ne voit
> pas — à traiter comme un premier déploiement, pas comme une formalité.

## Organisation

```
bootstrap/            À appliquer UNE FOIS, à la main : bucket d'état + compte de service Terraform
                      + fédération d'identité GitHub Actions (aucune clé JSON à stocker)
modules/              Briques réutilisables (network, cloud-sql, redis, storage, artifact-registry,
                      secret-manager, cloud-run-service, cloud-run-job, monitoring, edge-cdn-armor)
environments/staging  Le seul environnement destiné à être appliqué pour l'instant
environments/production  Squelette du même gabarit, valeurs de production — NON appliqué
templates/            SQL de création des rôles applicatifs (mots de passe générés par Terraform)
```

Staging et production sont **deux projets GCP distincts** (blueprint 12, §1) : jamais deux
environnements dans le même projet.

## Ce que tu dois faire toi-même (rien de ceci n'est automatisable ici)

1. Un compte Google Cloud avec **facturation activée** et l'outil `gcloud`
   ([installation](https://cloud.google.com/sdk/docs/install)) : `gcloud auth login` puis
   `gcloud auth application-default login`.
2. Créer le projet staging : `gcloud projects create thy-staging-XXXXXX` puis le rattacher à ta
   facturation (`gcloud billing projects link thy-staging-XXXXXX --billing-account=XXXXXX-XXXXXX-XXXXXX`).
   L'identifiant de projet est unique mondialement : choisis-en un libre.
3. Installer Terraform ≥ 1.9 (ou OpenTofu).

Ces ressources **facturent en continu** dès qu'elles existent, même sans trafic (Cloud SQL,
Memorystore, connecteur d'accès VPC). `terraform destroy` sur staging quand tu ne l'utilises pas.

## Premier déploiement, dans l'ordre

### 1. Bootstrap (une fois par projet)

```bash
cd infra/terraform/bootstrap
terraform init
terraform apply -var project_id=thy-staging-XXXXXX -var name_prefix=thy-staging
```

Note les sorties : `state_bucket_name`, `terraform_service_account_email`,
`workload_identity_provider`. Le state de `bootstrap/` reste **local** (il crée le bucket qui
hébergera les autres) : garde `terraform.tfstate` en lieu sûr.

### 2. Première passe : tout sauf Cloud Run

Un service/job Cloud Run refuse de se créer si son image n'existe pas dans Artifact Registry — or le
registre lui-même est créé par ce même Terraform. D'où deux passes :

```bash
cd infra/terraform/environments/staging
cp backend.hcl.example backend.hcl            # y mettre state_bucket_name
cp terraform.tfvars.example terraform.tfvars  # y mettre project_id, notification_email
terraform init -backend-config=backend.hcl
terraform apply \
  -target=google_project_service.required \
  -target=module.network -target=module.artifact_registry -target=module.cloud_sql \
  -target=module.redis -target=module.storage -target=module.secrets
```

(Cloud SQL et Memorystore mettent une dizaine de minutes à se créer.)

### 3. Construire et pousser l'image

Depuis la **racine du dépôt** (le contexte de build doit être la racine : espace de travail pnpm) :

```bash
REPO=$(terraform -chdir=infra/terraform/environments/staging output -raw artifact_registry_url)
gcloud auth configure-docker europe-west1-docker.pkg.dev
docker build --platform linux/amd64 -f backend/Dockerfile -t "$REPO/api:$(git rev-parse --short HEAD)" .
docker push "$REPO/api:$(git rev-parse --short HEAD)"
```

Reporte le tag poussé dans `api_image` de `terraform.tfvars`.

### 4. Seconde passe : tout

```bash
terraform apply   # crée le job migrate, le service api, les alertes
```

### 5. Créer les rôles applicatifs (`thy_app`, `thy_readonly`, `thy_admin_app`)

Terraform crée le rôle `thy_migrator` (propriétaire du schéma) mais **pas** `thy_app`, le rôle
`NOBYPASSRLS` que l'API utilise réellement — la RLS ne protège que si l'API ne se connecte jamais
en `thy_migrator` (ADR-004). Son mot de passe est déjà dans Secret Manager (`…-database-url`) ; il
faut créer le rôle avec **ce même mot de passe**, une fois :

```bash
terraform output -raw bootstrap_roles_sql > bootstrap-roles.rendered.sql   # contient des mots de passe, gitignoré
cloud-sql-proxy "$(terraform output -raw cloud_sql_connection_name)" &
# le mot de passe de thy_migrator est en tête du fichier rendu (commentaire d'usage)
psql -h 127.0.0.1 -U thy_migrator -d thy -v ON_ERROR_STOP=1 -f bootstrap-roles.rendered.sql
rm bootstrap-roles.rendered.sql
```

### 6. Migrations puis vérification

```bash
gcloud run jobs execute thy-staging-migrate --region europe-west1 --wait
curl "$(terraform output -raw api_url)/health/ready"    # {"status":"ok"}
```

C'est le critère de sortie de L0.4 : `terraform apply` provisionne staging, le kernel répond sur
`/health`.

## Choix et limites connus

- **`NODE_ENV=development` en staging.** En `production`, `validateConfig()` (`backend/src/kernel/config/config.ts`)
  refuse de démarrer sans fournisseur SMS réel ni adaptateur de stockage S3/GCS — aucun des deux
  n'existe encore (L0.8). Le squelette `production/` est volontairement réglé sur `production` : il
  **refusera** de démarrer tant que ce n'est pas écrit, ce qui est le garde-fou voulu.
- **Le bucket Cloud Storage et sa clé HMAC existent mais rien ne les utilise** (le kernel n'a qu'un
  adaptateur disque local). Sur Cloud Run, le disque est éphémère : les envois de fichiers ne
  survivront pas à une révision tant que l'adaptateur GCS n'est pas écrit.
- **Pas de `worker`** : ce process n'existe pas dans le code (`backend/` = API + migrateur). Le
  module `cloud-run-service` le déploiera tel quel le jour venu.
- **`edge-cdn-armor` (Cloud CDN + Cloud Armor) est écrit et validé mais non instancié** : il exige un
  nom de domaine pour le certificat managé, décision qui n'est pas prise. Pour l'activer :
  instancier le module dans `environments/staging/main.tf` avec `domain_name`, appliquer, créer
  l'enregistrement DNS A vers `static_ip_address`, réappliquer. L'API reste joignable en attendant
  par son URL `*.run.app`.
- **Redis sans TLS** (AUTH seulement) : le client du kernel (`kernel/redis/redis.service.ts`) ne
  configure pas TLS. À durcir ensemble, code et infra.
- **Egress non restreint** (blueprint 12 §2 « egress contrôlé ») : Cloud NAT + route par défaut
  supprimée, à faire en Phase 1.
- **Un seul compte de service d'exécution** pour `api` et `migrate` (Phase 0). Un compte par
  service serait plus strict.
- **Rôles du compte de service Terraform larges** (`bootstrap/main.tf`) : à resserrer une fois le
  périmètre stable.
- **L'image pèse ~1 Go** : `node_modules` est copié tel quel, devDependencies comprises
  (voir le commentaire du `Dockerfile`). Élaguer (`pnpm deploy`) est une optimisation à part.
- **Pas encore de déploiement automatique** (`cd-staging.yml`) : il dépend d'un projet GCP réel et
  des sorties du bootstrap (fédération d'identité), donc à écrire et tester après le premier
  `apply` réussi.
