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
  type = string
}

variable "private_vpc_connection" {
  description = "Force Terraform à attendre le peering du module network avant de créer l'instance."
  type        = any
}

variable "tier" {
  description = "BASIC (staging, pas de réplique) ou STANDARD_HA (production)."
  type        = string
  default     = "BASIC"
}

variable "memory_size_gb" {
  type    = number
  default = 1
}

variable "redis_version" {
  type    = string
  default = "REDIS_7_2"
}
