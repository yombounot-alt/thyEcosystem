# ADR-012 — Hébergement, cloud et région

- **Statut** : Acceptée (2026-09-22), région appliquée le 2026-09-26

| Option                                                                                  | Avantages                                                                                         | Inconvénients                                                                |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| **A. Conteneurs managés (AWS ECS Fargate ou GCP Cloud Run) + PostgreSQL/Redis managés** | Ops légères, PITR, scaling, services natifs (stockage objet, secret manager, logs) ; IaC portable | Coût > VPS ; verrouillage modéré (atténué par Docker, PG, API compatible S3) |
| B. Kubernetes managé                                                                    | Puissance, portabilité                                                                            | Surdimensionné pour 8 personnes en Phase 0–3                                 |
| C. PaaS (Render/Railway/Fly)                                                            | Très rapide                                                                                       | PostGIS/PITR/région/conformité variables ; coûts à l'échelle                 |
| D. Hébergeurs UE économiques (Scaleway/OVH/Hetzner)                                     | Coût minimal                                                                                      | Plus d'exploitation manuelle ; services managés moins riches                 |

**Décision validée (2026-09-22) : A — GCP.** Services retenus : **Cloud Run** (`api`, `worker`, job `migrate`), **Cloud SQL for PostgreSQL** (extension PostGIS supportée nativement), **Memorystore for Redis** (mode `noeviction` pour les files BullMQ), **Cloud Storage** (accès objet — le port `ObjectStorage` du kernel utilise l'API d'interopérabilité compatible S3 de GCS, donc aucun changement d'adaptateur si on migre plus tard), **Secret Manager**, **Cloud CDN + Cloud Armor** (WAF), **Artifact Registry** (images), **Cloud Logging/Monitoring** en base avant bascule vers la stack Grafana ([ADR-017](0017-observabilite.md)).
Région : **`europe-west1` (Belgique) par défaut, appliquée le 2026-09-26** — faute de mesure de latence disponible depuis les réseaux mobiles ouest-africains, ce qui est le repli prévu par le plan de la Phase 0 (§2 de `docs/plans/phase-0-foundation.md`) ; `europe-west4` (Pays-Bas) reste la candidate à comparer. Pas de région GCP en Afrique de l'Ouest à ce jour. Ce choix est **réversible tant que rien n'est déployé** : c'est une seule variable Terraform (`region`), mais changer de région une fois Cloud SQL peuplé est une migration de données, pas un simple `apply` — à mesurer avant la production, pas après. **IaC (Terraform, provider `google`)** dans `infra/terraform/` (L0.4) : modules réutilisables + un dossier par environnement, staging et production dans des **projets GCP distincts**. Rester portable : Docker, PostgreSQL standard, API compatible S3, aucun service propriétaire structurant au niveau applicatif.
**Reste à trancher** : budget mensuel cible (dimensionne les instances Cloud SQL/Memorystore et les seuils d'alerte de coût).

## Mise en œuvre (constat du 2026-10-17)

- Terraform écrit dans `infra/terraform/` (staging + squelette production), **jamais appliqué** : aucun projet GCP n'existe encore.
- Stockage objet par l'API compatible S3 (adaptateur `S3StorageAdapter`) ; en local et en CI, RustFS ([ADR-019](0019-stockage-objet-compatible-s3-rustfs-en-local-et-en-ci.md)).
