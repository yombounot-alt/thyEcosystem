output "repository_id" {
  value = google_artifact_registry_repository.images.repository_id
}

output "docker_repository_url" {
  description = "Préfixe à utiliser pour `docker push` (ex. .../thy-staging-images/api:SHA)."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}
