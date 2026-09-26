# Environnement STAGING — le seul appliqué pour l'instant (L0.4). production/ est un squelette du
# même gabarit, pas encore appliqué (docs/plans/phase-0-foundation.md L0.4).
#
# Prérequis : voir README.md de ce dossier (projet GCP créé + facturation activée, bootstrap déjà
# appliqué une fois). "worker" n'est pas déployé : ce process n'existe pas encore dans le code
# (backend/ n'a qu'une API + un migrateur — voir docs/plans/consolidation-strategy.md).

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "gcs" {
    # Rempli via `terraform init -backend-config=backend.hcl` (voir backend.hcl.example) : le nom du
    # bucket dépend du projet GCP, connu seulement après le bootstrap.
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─── APIs GCP requises ─────────────────────────────────────────────────────────────────────────
resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ─── Réseau ────────────────────────────────────────────────────────────────────────────────────
module "network" {
  source      = "../../modules/network"
  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  depends_on  = [google_project_service.required]
}

# ─── Registre d'images ─────────────────────────────────────────────────────────────────────────
module "artifact_registry" {
  source      = "../../modules/artifact-registry"
  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  depends_on  = [google_project_service.required]
}

# ─── Secrets générés par Terraform (jamais tapés à la main) ───────────────────────────────────────
resource "random_password" "db_migrator" {
  length  = 32
  special = false # simplifie le collage manuel dans bootstrap-roles.sql / psql
}
resource "random_password" "db_app" {
  length  = 32
  special = false
}
resource "random_password" "db_readonly" {
  length  = 32
  special = false
}
resource "random_password" "db_admin_app" {
  length  = 32
  special = false
}
resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}
resource "random_password" "hmac_pepper" {
  length  = 48
  special = false
}

# ─── Base de données ───────────────────────────────────────────────────────────────────────────
module "cloud_sql" {
  source                 = "../../modules/cloud-sql"
  project_id             = var.project_id
  region                 = var.region
  name_prefix            = var.name_prefix
  network_id             = module.network.network_id
  private_vpc_connection = module.network.private_vpc_connection
  migrator_password      = random_password.db_migrator.result
  # Staging : pas de trafic, coût minimal, destructible sans friction.
  tier                = "db-g1-small"
  availability_type   = "ZONAL"
  deletion_protection = false
}

# ─── Cache ─────────────────────────────────────────────────────────────────────────────────────
module "redis" {
  source                 = "../../modules/redis"
  project_id             = var.project_id
  region                 = var.region
  name_prefix            = var.name_prefix
  network_id             = module.network.network_id
  private_vpc_connection = module.network.private_vpc_connection
  tier                   = "BASIC"
  memory_size_gb         = 1
}

# ─── Stockage objet ────────────────────────────────────────────────────────────────────────────
module "storage" {
  source        = "../../modules/storage"
  project_id    = var.project_id
  region        = var.region
  name_prefix   = var.name_prefix
  force_destroy = true # staging seulement — jamais en production
}

# ─── Identité d'exécution (api + job migrate) ─────────────────────────────────────────────────
resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-runtime"
  display_name = "THY — api + migrate (${var.name_prefix})"
}

locals {
  database_url          = "postgres://thy_app:${random_password.db_app.result}@${module.cloud_sql.private_ip_address}:5432/${module.cloud_sql.database_name}"
  migrator_database_url = "postgres://${module.cloud_sql.migrator_user}:${random_password.db_migrator.result}@${module.cloud_sql.private_ip_address}:5432/${module.cloud_sql.database_name}"
  redis_url             = "redis://:${module.redis.auth_string}@${module.redis.host}:${module.redis.port}"
}

module "secrets" {
  source      = "../../modules/secret-manager"
  project_id  = var.project_id
  name_prefix = var.name_prefix
  generated_secret_values = {
    "database-url"          = local.database_url
    "migrator-database-url" = local.migrator_database_url
    "redis-url"             = local.redis_url
    "jwt-secret"            = random_password.jwt_secret.result
    "hmac-pepper"           = random_password.hmac_pepper.result
  }
  # Pas encore de fournisseur SMS/PSP réel en Phase 0 (voir docs/plans/phase-0-foundation.md L0.6) :
  # ces conteneurs existent pour que le jour où un vrai fournisseur arrive, il n'y ait qu'une
  # `gcloud secrets versions add` à faire, jamais un nouveau `terraform apply` de la forme du secret.
  secret_ids                = ["sms-provider-api-key"]
  accessor_service_accounts = [google_service_account.runtime.email]
}

# ─── Migration (job, exécuté avant chaque déploiement de l'API — voir README) ─────────────────
module "migrate_job" {
  source                = "../../modules/cloud-run-job"
  project_id            = var.project_id
  region                = var.region
  name                  = "${var.name_prefix}-migrate"
  image                 = var.api_image
  command               = ["node", "dist/database/migrate-cli.js"]
  service_account_email = google_service_account.runtime.email
  vpc_connector_id      = module.network.vpc_connector_id
  secret_env = {
    MIGRATOR_DATABASE_URL = module.secrets.secret_ids["migrator-database-url"]
  }

  # Les droits de lecture des secrets (IAM, dans module.secrets) doivent exister AVANT que la
  # première révision démarre — sinon elle échoue à résoudre ses variables d'environnement.
  depends_on = [module.secrets]
}

# ─── API ───────────────────────────────────────────────────────────────────────────────────────
module "api" {
  source                = "../../modules/cloud-run-service"
  project_id            = var.project_id
  region                = var.region
  name                  = "${var.name_prefix}-api"
  image                 = var.api_image
  service_account_email = google_service_account.runtime.email
  vpc_connector_id      = module.network.vpc_connector_id
  container_port        = 8080
  min_instance_count    = 0
  max_instance_count    = 3
  allow_unauthenticated = true

  env = {
    # NODE_ENV=development, pas "production" : c'est un premier déploiement de fumée (voir L0.4,
    # "image vide … répond sur /health"). En "production", validateConfig() (config.ts) exige un
    # fournisseur SMS réel et un adaptateur de stockage S3/GCS — aucun des deux n'existe encore
    # dans le code (L0.8). Repasser à "production" quand ce sera fait, pas avant.
    NODE_ENV    = "development"
    TRUST_PROXY = "true" # Cloud Run est un proxy inverse : sans ça, req.ip vaudrait l'IP interne de Google
    DB_POOL_MAX = "5"    # instance db-g1-small : peu de connexions simultanées supportées
  }
  secret_env = {
    DATABASE_URL          = module.secrets.secret_ids["database-url"]
    MIGRATOR_DATABASE_URL = module.secrets.secret_ids["migrator-database-url"]
    REDIS_URL             = module.secrets.secret_ids["redis-url"]
    JWT_SECRET            = module.secrets.secret_ids["jwt-secret"]
    HMAC_PEPPER           = module.secrets.secret_ids["hmac-pepper"]
  }

  depends_on = [module.secrets]
}

# ─── Observabilité de base ─────────────────────────────────────────────────────────────────────
module "monitoring" {
  source                 = "../../modules/monitoring"
  project_id             = var.project_id
  name_prefix            = var.name_prefix
  notification_email     = var.notification_email
  api_service_host       = replace(module.api.url, "https://", "")
  cloud_run_service_name = module.api.name
}

