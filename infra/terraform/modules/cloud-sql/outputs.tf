output "connection_name" {
  description = "Pour le connecteur Cloud SQL Auth Proxy (accès depuis un poste de développement, hors du VPC)."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  value = google_sql_database_instance.this.private_ip_address
}

output "database_name" {
  value = google_sql_database.app.name
}

output "migrator_user" {
  value = google_sql_user.migrator.name
}

output "instance_name" {
  value = google_sql_database_instance.this.name
}
