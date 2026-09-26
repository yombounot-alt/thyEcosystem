# Observabilité de base (Cloud Monitoring/Logging) avant bascule vers Grafana/Tempo/Loki — ADR-017.
# Deux alertes minimales : la sonde /health/ready ne répond plus, ou le taux de 5xx grimpe.

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "THY — alertes (${var.name_prefix})"
  type         = "email"
  labels = {
    email_address = var.notification_email
  }
}

resource "google_monitoring_uptime_check_config" "api_health" {
  project      = var.project_id
  display_name = "${var.name_prefix}-api-health"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/health/ready"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.api_service_host
    }
  }
}

resource "google_monitoring_alert_policy" "uptime_failure" {
  project      = var.project_id
  display_name = "${var.name_prefix} — API indisponible (/health/ready)"
  combiner     = "OR"

  conditions {
    display_name = "Échec de la sonde de disponibilité"
    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.\"check_id\"=\"${google_monitoring_uptime_check_config.api_health.uptime_check_id}\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "60s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}

resource "google_monitoring_alert_policy" "error_rate" {
  project      = var.project_id
  display_name = "${var.name_prefix} — taux d'erreur 5xx élevé (${var.cloud_run_service_name})"
  combiner     = "OR"

  conditions {
    display_name = "Requêtes 5xx"
    condition_threshold {
      filter = join(" AND ", [
        "resource.type=\"cloud_run_revision\"",
        "resource.label.\"service_name\"=\"${var.cloud_run_service_name}\"",
        "metric.type=\"run.googleapis.com/request_count\"",
        "metric.label.\"response_code_class\"=\"5xx\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}
