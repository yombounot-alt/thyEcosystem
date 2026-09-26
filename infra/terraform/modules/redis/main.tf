# Redis managé (Memorystore). `noeviction` : les files/idempotence/rate-limit du kernel doivent
# échouer bruyamment plutôt que perdre silencieusement des clés sous pression mémoire (voir
# docs/blueprint/03-database.md, infra/docker/compose.dev.yml qui pose déjà --maxmemory-policy
# noeviction en local). IP privée uniquement, AUTH activé (jamais de cache exposé sans mot de passe).

resource "google_redis_instance" "this" {
  project        = var.project_id
  name           = "${var.name_prefix}-redis"
  region         = var.region
  tier           = var.tier
  memory_size_gb = var.memory_size_gb
  redis_version  = var.redis_version

  authorized_network = var.network_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  # Le chiffrement en transit (TLS) demande un client Redis configuré pour ça ; le kernel
  # (kernel/redis/redis.service.ts) ne le fait pas encore — AUTH (mot de passe) suffit pour
  # l'instant, TLS est un durcissement séparé à faire quand le client sera prêt.
  transit_encryption_mode = "DISABLED"
  auth_enabled            = true

  redis_configs = {
    "maxmemory-policy" = "noeviction"
  }

  depends_on = [var.private_vpc_connection]
}
