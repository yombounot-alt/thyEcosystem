output "state_bucket_name" {
  description = "À reporter dans environments/<env>/backend.hcl."
  value       = google_storage_bucket.tf_state.name
}

output "terraform_service_account_email" {
  value = google_service_account.terraform.email
}

output "workload_identity_provider" {
  description = "À utiliser comme `workload_identity_provider` de google-github-actions/auth dans le workflow de déploiement."
  value       = "projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
}
