variable "project_id" {
  description = "Projet GCP dans lequel créer le réseau."
  type        = string
}

variable "region" {
  description = "Région du sous-réseau et du connecteur d'accès serverless."
  type        = string
}

variable "name_prefix" {
  description = "Préfixe des ressources (ex. \"thy-staging\")."
  type        = string
}

variable "subnet_cidr" {
  description = "Plage IP du sous-réseau régional (Cloud Run direct-egress, VPC connector)."
  type        = string
  default     = "10.10.0.0/20"
}

variable "private_services_cidr_prefix_length" {
  description = "Longueur de préfixe de la plage réservée pour l'accès privé aux services (Cloud SQL, Memorystore)."
  type        = number
  default     = 20
}

variable "connector_cidr" {
  description = "Plage /28 dédiée au connecteur d'accès VPC serverless (doit être distincte de subnet_cidr)."
  type        = string
  default     = "10.10.16.0/28"
}
