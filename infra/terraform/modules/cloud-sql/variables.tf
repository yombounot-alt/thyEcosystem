variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "network_id" {
  description = "VPC dans lequel attribuer l'IP privée de l'instance."
  type        = string
}

variable "private_vpc_connection" {
  description = "Sortie google_service_networking_connection du module network — force Terraform à attendre le peering avant de créer l'instance."
  type        = any
}

variable "database_version" {
  type    = string
  default = "POSTGRES_17"
}

variable "tier" {
  description = "Palier machine Cloud SQL. db-g1-small suffit pour un staging sans trafic (voir L0.4)."
  type        = string
  default     = "db-g1-small"
}

variable "availability_type" {
  description = "ZONAL (staging, moins cher) ou REGIONAL (haute dispo, production)."
  type        = string
  default     = "ZONAL"
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "deletion_protection" {
  description = "true en production. false en staging pour permettre un `terraform destroy` propre."
  type        = bool
  default     = false
}

variable "database_name" {
  type    = string
  default = "thy"
}

variable "backup_start_time" {
  description = "Heure UTC de la sauvegarde quotidienne (HH:MM)."
  type        = string
  default     = "03:00"
}

variable "migrator_user" {
  description = "Rôle propriétaire du schéma, utilisé UNIQUEMENT par le migrateur (thy_migrator — voir ADR-004, backend/src/kernel/config/config.ts)."
  type        = string
  default     = "thy_migrator"
}

variable "migrator_password" {
  description = "Généré par l'environnement appelant (random_password), jamais écrit en clair dans un fichier .tf."
  type        = string
  sensitive   = true
}

