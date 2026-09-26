variable "project_id" {
  description = "Projet GCP (staging ou production) à préparer pour Terraform."
  type        = string
}

variable "region" {
  type    = string
  default = "europe-west1" # voir ADR-012 : par défaut faute de mesure de latence disponible
}

variable "name_prefix" {
  description = "Ex. \"thy-staging\" ou \"thy-production\" — préfixe du bucket d'état et du compte de service."
  type        = string
}

variable "github_repository" {
  description = "\"owner/repo\" autorisé à s'authentifier via Workload Identity Federation (ex. \"yombounot-alt/thyEcosystem\")."
  type        = string
  default     = "yombounot-alt/thyEcosystem"
}
