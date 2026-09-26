# Un seul dépôt Docker par environnement (staging/production sont des projets GCP distincts, donc
# déjà isolés) ; les images backend/admin y partagent le même dépôt, distinguées par nom d'image.
resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.name_prefix}-images"
  format        = "DOCKER"
  description   = "Images conteneur THY (api, migrate, admin) — ${var.name_prefix}"

  cleanup_policies {
    id     = "keep-last-20"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }

  cleanup_policies {
    id     = "delete-untagged-after-7d"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "7d"
    }
  }
}
