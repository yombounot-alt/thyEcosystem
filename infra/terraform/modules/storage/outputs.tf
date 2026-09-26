output "bucket_name" {
  value = google_storage_bucket.this.name
}

output "hmac_access_id" {
  value = google_storage_hmac_key.this.access_id
}

output "hmac_secret" {
  value     = google_storage_hmac_key.this.secret
  sensitive = true
}
