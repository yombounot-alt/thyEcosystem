# Job Cloud Run — utilisé pour "migrate" : s'exécute une fois (`gcloud run jobs execute`, ou une
# étape de pipeline de déploiement), jamais en continu. "Job migrate avant le déploiement des
# applications" (docs/blueprint/12-devops-monitoring.md §3.2).

resource "google_cloud_run_v2_job" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region

  template {
    template {
      service_account = var.service_account_email
      timeout         = "${var.timeout_seconds}s"
      max_retries     = 0 # une migration ratée ne se rejoue pas seule : elle doit être regardée

      vpc_access {
        connector = var.vpc_connector_id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image   = var.image
        command = var.command

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        dynamic "env" {
          for_each = var.env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = var.secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }
}
