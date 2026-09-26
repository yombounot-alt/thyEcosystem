# À appliquer UNE FOIS, à la main, avec les identifiants gcloud d'un humain (voir README.md de ce
# dossier) — jamais depuis la CI, et jamais avec le state distant : ce module CRÉE le bucket que le
# state distant utilisera ensuite, donc son propre state reste local (fichier `terraform.tfstate`,
# à garder en lieu sûr — il contient les identifiants du pool d'identité, pas de secret applicatif).

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_project_service" "required" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ─── Bucket d'état Terraform ──────────────────────────────────────────────────────────────────────
resource "google_storage_bucket" "tf_state" {
  project                     = var.project_id
  name                        = "${var.name_prefix}-tfstate-${var.project_id}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  public_access_prevention = "enforced"
}

# ─── Compte de service utilisé par Terraform (staging/production) ────────────────────────────────
resource "google_service_account" "terraform" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-terraform"
  display_name = "THY — Terraform CI (${var.name_prefix})"
}

# Rôles larges mais nommés (pas "roles/editor") : à resserrer par la suite si besoin, chaque rôle
# correspondant à un module de infra/terraform/modules/*.
resource "google_project_iam_member" "terraform_roles" {
  for_each = toset([
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/compute.loadBalancerAdmin",
    "roles/cloudsql.admin",
    "roles/redis.admin",
    "roles/storage.admin",
    "roles/secretmanager.admin",
    "roles/artifactregistry.admin",
    "roles/run.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/monitoring.editor",
    "roles/servicenetworking.networksAdmin",
    "roles/serviceusage.serviceUsageAdmin",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# ─── Fédération d'identité de charge de travail (GitHub Actions → ce compte de service) ───────────
# Pas de clé JSON de compte de service à faire vivre dans un secret CI : GitHub Actions échange le
# jeton OIDC de son job contre une identité GCP à la volée, restreinte à CE dépôt.
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.name_prefix}-github"
  display_name              = "GitHub Actions (${var.name_prefix})"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  # Restreint aux workflows du dépôt THY sur main : un fork ou une autre branche ne peut pas
  # emprunter ce compte de service.
  attribute_condition = "assertion.repository == \"${var.github_repository}\" && assertion.ref == \"refs/heads/main\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}
