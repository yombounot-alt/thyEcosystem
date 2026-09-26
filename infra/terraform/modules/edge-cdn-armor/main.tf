# Module OPTIONNEL : Cloud CDN + Cloud Armor devant l'API, via un load balancer HTTPS externe et un
# "serverless NEG" (Cloud Run ne peut pas être placé derrière Cloud Armor directement). Non instancié
# par environments/staging tant qu'aucun nom de domaine n'est choisi pour le staging — voir le
# README d'infra/terraform. Rien ici n'a de sens sans `domain_name`.

resource "google_compute_security_policy" "this" {
  project     = var.project_id
  name        = "${var.name_prefix}-armor"
  description = "Cloud Armor — devant l'API THY (${var.name_prefix})"

  # Règles OWASP preconfigurées (XSS, injection SQL…) — base raisonnable avant tout tuning applicatif.
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
    description = "Bloque les tentatives XSS connues (règles préconfigurées Google)."
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "Bloque les tentatives d'injection SQL connues (règles préconfigurées Google)."
  }

  rule {
    action   = "throttle"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_threshold_count
        interval_sec = var.rate_limit_interval_sec
      }
    }
    description = "Limite de débit par IP — protège des abus simples, pas une défense DDoS volumétrique."
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Règle par défaut obligatoire."
  }
}

resource "google_compute_region_network_endpoint_group" "api" {
  project               = var.project_id
  name                  = "${var.name_prefix}-api-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = var.cloud_run_service_name
  }
}

resource "google_compute_backend_service" "api" {
  project               = var.project_id
  name                  = "${var.name_prefix}-api-backend"
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.this.id
  enable_cdn            = true

  # Un backend Cloud Run n'a de sens à mettre en cache que pour des réponses explicitement
  # cacheables (assets publics futurs — l'admin, par ex.) : l'API elle-même répond `Cache-Control`
  # au cas par cas, jamais par défaut ici.
  cdn_policy {
    cache_mode = "USE_ORIGIN_HEADERS"
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = true
    }
  }

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }
}

resource "google_compute_url_map" "https" {
  project         = var.project_id
  name            = "${var.name_prefix}-api-urlmap"
  default_service = google_compute_backend_service.api.id
}

resource "google_compute_managed_ssl_certificate" "this" {
  project = var.project_id
  name    = "${var.name_prefix}-api-cert"
  managed {
    domains = [var.domain_name]
  }
}

resource "google_compute_target_https_proxy" "this" {
  project          = var.project_id
  name             = "${var.name_prefix}-api-https-proxy"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.this.id]
}

resource "google_compute_global_address" "lb_ip" {
  project = var.project_id
  name    = "${var.name_prefix}-api-lb-ip"
}

resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = "${var.name_prefix}-api-https-fr"
  target                = google_compute_target_https_proxy.this.id
  port_range            = "443"
  ip_address            = google_compute_global_address.lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# Redirection HTTP → HTTPS (le port 80 ne sert jamais l'API en clair).
resource "google_compute_url_map" "http_redirect" {
  project = var.project_id
  name    = "${var.name_prefix}-api-http-redirect"
  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "${var.name_prefix}-api-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project               = var.project_id
  name                  = "${var.name_prefix}-api-http-fr"
  target                = google_compute_target_http_proxy.redirect.id
  port_range            = "80"
  ip_address            = google_compute_global_address.lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
