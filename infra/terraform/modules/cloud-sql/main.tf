# PostgreSQL managé (Cloud SQL). PostGIS est fourni par l'image Cloud SQL Postgres mais n'est PAS
# activé ici : comme en local et en CI (voir infra/docker/postgres/init/02-extensions.sql et
# .github/workflows/ci-backend.yml), les extensions sont créées par le migrateur applicatif
# (backend/src/database/migrate.ts), pas par Terraform — un `CREATE EXTENSION` a besoin d'une
# connexion SQL réelle, que l'IaC n'a pas de raison fiable d'ouvrir pendant un `apply`.
#
# IP privée uniquement (jamais d'IP publique) : seul le VPC (donc Cloud Run via le connecteur
# serverless) peut joindre l'instance.

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = "${var.name_prefix}-pg"
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  depends_on = [var.private_vpc_connection]

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_size         = var.disk_size_gb
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
    }

    maintenance_window {
      day  = 7 # dimanche
      hour = 4 # 04:00 UTC
    }

    insights_config {
      query_insights_enabled = true
    }
  }
}

resource "google_sql_database" "app" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.this.name
}

# Rôle superutilisateur Cloud SQL (cloudsqlsuperuser) : c'est LUI qui exécute les migrations et crée
# ensuite thy_app/thy_readonly/thy_admin_app (voir infra/docker/postgres/init/01-roles.sql, rejoué
# manuellement une fois contre cette instance — le migrateur applicatif ne crée pas ces rôles).
resource "google_sql_user" "migrator" {
  project  = var.project_id
  name     = var.migrator_user
  instance = google_sql_database_instance.this.name
  password = var.migrator_password
}
