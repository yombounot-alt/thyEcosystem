variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "notification_email" {
  description = "Adresse recevant les alertes (disponibilité, taux d'erreur 5xx). Une seule pour l'instant — un canal de rotation d'astreinte viendra avec l'équipe (docs/blueprint/12-devops-monitoring.md §4)."
  type        = string
}

variable "api_service_host" {
  description = "Hôte HTTPS de la sonde de disponibilité (ex. l'URL Cloud Run de l'API, sans le schéma)."
  type        = string
}

variable "cloud_run_service_name" {
  description = "Nom du service Cloud Run surveillé pour le taux d'erreur 5xx."
  type        = string
}
