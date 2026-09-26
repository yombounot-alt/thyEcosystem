# Conteneurs Secret Manager. AUCUNE valeur de secret ne vit dans un fichier .tf ou dans le dépôt :
# soit Terraform l'a générée lui-même (random_password, jamais tapée par un humain) et en verse la
# première version ici, soit le secret reste sans version jusqu'à ce qu'un humain fasse
# `gcloud secrets versions add <nom> --data-file=-` (fournisseurs SMS/PSP, clés tierces — rien de
# tel n'existe encore en Phase 0).

locals {
  # Terraform interdit d'itérer (for_each) sur une valeur sensible. Ce sont les VALEURS qui sont
  # secrètes, pas les noms logiques des secrets (clés de la map) : on les extrait explicitement.
  generated_names  = toset(nonsensitive(keys(var.generated_secret_values)))
  all_secret_names = toset(concat(var.secret_ids, tolist(local.generated_names)))
}

resource "google_secret_manager_secret" "this" {
  for_each  = local.all_secret_names
  project   = var.project_id
  secret_id = "${var.name_prefix}-${each.value}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "generated" {
  for_each    = local.generated_names
  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = var.generated_secret_values[each.key]
}

resource "google_secret_manager_secret_iam_member" "accessors" {
  for_each = {
    for pair in setproduct(tolist(local.all_secret_names), var.accessor_service_accounts) :
    "${pair[0]}:${pair[1]}" => pair
  }
  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value[0]].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value[1]}"
}
