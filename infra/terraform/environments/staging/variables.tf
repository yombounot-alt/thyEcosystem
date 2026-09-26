variable "project_id" {
  description = "Projet GCP staging (voir infra/terraform/bootstrap et le README de ce dossier)."
  type        = string
}

variable "region" {
  type    = string
  default = "europe-west1" # ADR-012 : par défaut faute de mesure de latence Afrique de l'Ouest
}

variable "name_prefix" {
  type    = string
  default = "thy-staging"
}

variable "notification_email" {
  description = "Reçoit les alertes de disponibilité/erreurs (voir modules/monitoring)."
  type        = string
}

variable "api_image" {
  description = <<-EOT
    Image complète du service "api" (ex. europe-west1-docker.pkg.dev/PROJET/thy-staging-images/api:SHA).
    Absente au premier `apply` : Artifact Registry doit exister avant qu'une image puisse y être
    poussée — voir le README pour l'ordre des opérations du tout premier déploiement.
  EOT
  type        = string
}
