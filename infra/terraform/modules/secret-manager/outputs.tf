output "secret_ids" {
  description = "Nom Secret Manager réel (préfixé) de chaque secret logique demandé."
  value       = { for name, s in google_secret_manager_secret.this : name => s.secret_id }
}
