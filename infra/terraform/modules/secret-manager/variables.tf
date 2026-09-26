variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "secret_ids" {
  description = "Noms logiques des secrets à créer (ex. [\"jwt-secret\", \"hmac-pepper\"]) — sans valeur : voir `generated_secret_values` pour les secrets que Terraform peut renseigner lui-même."
  type        = list(string)
  default     = []
}

variable "generated_secret_values" {
  description = <<-EOT
    Secrets dont Terraform CONNAÎT la valeur au moment de l'apply (générée par `random_password`
    dans l'environnement appelant) et peut donc verser directement — jamais un secret tiers
    (fournisseur SMS, PSP…), qui n'existe nulle part avant qu'un humain ne le fournisse.
    Map nom-logique => valeur.
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "accessor_service_accounts" {
  description = "Comptes de service autorisés à LIRE ces secrets (roles/secretmanager.secretAccessor)."
  type        = list(string)
  default     = []
}
