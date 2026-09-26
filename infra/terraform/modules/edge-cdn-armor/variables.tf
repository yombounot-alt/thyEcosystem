variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "region" {
  description = "Région du service Cloud Run mis en façade."
  type        = string
}

variable "cloud_run_service_name" {
  type = string
}

variable "domain_name" {
  description = <<-EOT
    Domaine servi par ce module (ex. "staging-api.thy.example"). Un certificat Google managé n'est
    délivré que si ce domaine pointe déjà (enregistrement DNS A) vers l'IP statique renvoyée par ce
    module — donc à créer APRÈS un premier `apply` qui expose `static_ip_address`, puis réappliquer.
  EOT
  type        = string
}

variable "rate_limit_threshold_count" {
  description = "Requêtes autorisées par IP sur la fenêtre ci-dessous avant blocage temporaire (Cloud Armor)."
  type        = number
  default     = 100
}

variable "rate_limit_interval_sec" {
  type    = number
  default = 60
}
