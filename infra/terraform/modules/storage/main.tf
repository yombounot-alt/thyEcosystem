# Stockage objet (photos produits, logos, preuves de paiement). Accès via l'API d'interopérabilité
# compatible S3 de GCS (ADR-012) : une clé HMAC, pas les identifiants GCP natifs, pour que le port
# `StoragePort` du kernel n'ait pas besoin d'un adaptateur spécifique à GCP.
#
# NB (2026-09) : le kernel n'a aujourd'hui qu'un adaptateur "disque local"
# (backend/src/kernel/storage/local-disk-storage.adapter.ts) ; un adaptateur S3/GCS reste à écrire
# (L0.8). Ce bucket existe donc par anticipation — rien ne l'utilise encore.

resource "google_storage_bucket" "this" {
  project                     = var.project_id
  name                        = "${var.name_prefix}-${var.project_id}-storage"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy

  versioning {
    enabled = true
  }

  # Retire les versions non courantes après 30 jours : la version courante n'est jamais purgée par
  # cette règle (elle ne cible que noncurrent_time).
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
    }
    action {
      type = "Delete"
    }
  }

  public_access_prevention = "enforced"
}

# Identité dédiée : ni le compte de service Cloud Run "api" ni un compte personnel ne doivent
# porter cette clé HMAC — un compte de service à un seul usage limite le rayon d'une fuite.
resource "google_service_account" "storage_hmac" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-storage-hmac"
  display_name = "THY — accès S3-compatible au bucket de stockage (${var.name_prefix})"
}

resource "google_storage_bucket_iam_member" "hmac_object_admin" {
  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.storage_hmac.email}"
}

resource "google_storage_hmac_key" "this" {
  project               = var.project_id
  service_account_email = google_service_account.storage_hmac.email
}
