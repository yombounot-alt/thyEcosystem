variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name" {
  type = string
}

variable "image" {
  type = string
}

variable "command" {
  description = "Override de l'entrypoint (ex. [\"node\", \"dist/database/migrate-cli.js\"])."
  type        = list(string)
  default     = null
}

variable "service_account_email" {
  type = string
}

variable "vpc_connector_id" {
  type = string
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "timeout_seconds" {
  type    = number
  default = 300
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "secret_env" {
  type    = map(string)
  default = {}
}
