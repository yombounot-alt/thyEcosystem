variable "project_id" {
  type = string
}

variable "region" {
  description = "Utilisée comme location du bucket (une seule région suffit en staging)."
  type        = string
}

variable "name_prefix" {
  type = string
}

variable "force_destroy" {
  description = "true en staging (permet un `terraform destroy` propre) ; false en production."
  type        = bool
  default     = false
}
