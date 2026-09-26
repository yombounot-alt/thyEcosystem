output "static_ip_address" {
  description = "À pointer via un enregistrement DNS A vers `var.domain_name` avant que le certificat managé ne se provisionne."
  value       = google_compute_global_address.lb_ip.address
}

output "security_policy_id" {
  value = google_compute_security_policy.this.id
}
