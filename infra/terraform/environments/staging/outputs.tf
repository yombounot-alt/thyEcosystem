output "api_url" {
  value = module.api.url
}

output "artifact_registry_url" {
  description = "Préfixe `docker push` pour les images api/migrate."
  value       = module.artifact_registry.docker_repository_url
}

output "cloud_sql_connection_name" {
  description = "Pour `cloud-sql-proxy` (accès depuis un poste, hors du VPC)."
  value       = module.cloud_sql.connection_name
}

output "storage_bucket_name" {
  value = module.storage.bucket_name
}

# À récupérer avec `terraform output -raw bootstrap_roles_sql`, jamais affiché en clair par un
# `terraform apply`/`plan` normal (sensitive = true) — voir README.md, §"Premier déploiement".
output "bootstrap_roles_sql" {
  sensitive = true
  value = templatefile("${path.module}/../../templates/bootstrap-roles.sql.tpl", {
    app_password       = random_password.db_app.result
    readonly_password  = random_password.db_readonly.result
    admin_app_password = random_password.db_admin_app.result
    database_name      = module.cloud_sql.database_name
    migrator_user      = module.cloud_sql.migrator_user
    migrator_password  = random_password.db_migrator.result
    connection_name    = module.cloud_sql.connection_name
  })
}
