output "network_id" {
  value = google_compute_network.this.id
}

output "network_name" {
  value = google_compute_network.this.name
}

output "subnetwork_id" {
  value = google_compute_subnetwork.primary.id
}

output "vpc_connector_id" {
  description = "À passer à google_cloud_run_v2_service.template.vpc_access.connector."
  value       = google_vpc_access_connector.serverless.id
}

output "private_vpc_connection" {
  description = "Dépendance explicite : Cloud SQL/Memorystore doivent attendre le peering avant de se créer."
  value       = google_service_networking_connection.private_service_connection
}
