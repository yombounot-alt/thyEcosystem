# Réseau privé du kernel THY : un VPC par environnement (staging/production sont deux PROJETS GCP
# séparés — voir docs/blueprint/12-devops-monitoring.md §1 — donc deux VPC totalement isolés, pas
# seulement deux sous-réseaux du même réseau).
#
# Cloud SQL et Memorystore ne sont joignables qu'en IP privée (jamais d'IP publique sur la base ou
# le cache) : Cloud Run les atteint via un connecteur d'accès VPC serverless.

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_subnetwork" "primary" {
  project       = var.project_id
  name          = "${var.name_prefix}-subnet-${var.region}"
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr
  # Nécessaire pour que Cloud Run (direct VPC egress) et GKE éventuel plus tard.
  private_ip_google_access = true
}

# ─── Accès privé aux services (Cloud SQL, Memorystore) ───────────────────────────────────────────
# Réserve une plage d'adresses pour le "VPC peering" que Google gère de son côté ; Cloud SQL et
# Memorystore y prennent une IP interne au VPC, jamais exposée sur Internet.
resource "google_compute_global_address" "private_service_range" {
  project       = var.project_id
  name          = "${var.name_prefix}-private-service-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_services_cidr_prefix_length
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "private_service_connection" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

# ─── Connecteur d'accès VPC serverless (Cloud Run → VPC) ─────────────────────────────────────────
resource "google_vpc_access_connector" "serverless" {
  project       = var.project_id
  name          = "${var.name_prefix}-connector"
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.connector_cidr
  # Le plus petit palier : suffisant pour api+migrate en Phase 0 (staging, pas de trafic réel).
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

# ─── Pare-feu ──────────────────────────────────────────────────────────────────────────────────
# Autorise uniquement le trafic interne au VPC (Cloud Run via le connecteur → Cloud SQL/Memorystore
# sur leurs ports). Tout le reste suit le comportement par défaut de GCP : ingress refusé, egress
# autorisé. Un egress restreint (Cloud NAT + route par défaut supprimée) est un durcissement à part,
# pas fait ici (voir docs/blueprint/12-devops-monitoring.md §2 "egress contrôlé" — TODO Phase 1).
resource "google_compute_firewall" "allow_internal" {
  project   = var.project_id
  name      = "${var.name_prefix}-allow-internal"
  network   = google_compute_network.this.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["5432", "6379"]
  }

  source_ranges = [var.subnet_cidr, var.connector_cidr]
}
