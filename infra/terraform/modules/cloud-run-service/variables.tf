variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name" {
  description = "Nom du service Cloud Run (ex. \"thy-staging-api\")."
  type        = string
}

variable "image" {
  description = "Image conteneur complète (ex. europe-west1-docker.pkg.dev/.../api:SHA)."
  type        = string
}

variable "service_account_email" {
  type = string
}

variable "vpc_connector_id" {
  type = string
}

variable "container_port" {
  type    = number
  default = 3000
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "min_instance_count" {
  description = "0 en staging (pas de trafic à absorber) : ne coûte rien tant que personne n'appelle."
  type        = number
  default     = 0
}

variable "max_instance_count" {
  type    = number
  default = 3
}

variable "allow_unauthenticated" {
  description = "true pour l'API publique ; false pour un service interne (ex. futur worker)."
  type        = bool
  default     = false
}

variable "env" {
  description = "Variables d'environnement en clair (jamais un secret — voir `secret_env`)."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Variables d'environnement lues depuis Secret Manager. Map nom de variable => secret_id Secret Manager."
  type        = map(string)
  default     = {}
}
