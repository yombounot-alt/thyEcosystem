# ADR-019 — Stockage objet compatible S3 : RustFS en local et en CI

- **Statut** : Acceptée (2026-09-28, commit `79e1f40`)
- **Complète** : [ADR-012](0012-hebergement-cloud-et-region.md)

## Contexte

Le kernel écrit les fichiers (images produit, pièces jointes) par un port `StoragePort`. En
staging et en production, l'adaptateur `S3StorageAdapter` parle à Cloud Storage par son API
d'interopérabilité compatible S3 ([ADR-012](0012-hebergement-cloud-et-region.md)). Il faut le
même protocole en local et en CI, sinon le chemin de production n'est jamais testé.

L'environnement local utilisait MinIO. Le 2026-09-28, la CI a échoué : les images `minio/minio`
et `minio/mc` ont été retirées de Docker Hub. Le cache Docker local masquait le problème.

## Options

| Option                                | Avantages                                             | Inconvénients                                                                |
| ------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------- |
| **A. RustFS (`rustfs/rustfs:1.0.0`)** | Compatible S3, image publique maintenue, démarre vite | Projet plus jeune que MinIO                                                  |
| B. Garder MinIO via une image tierce  | Aucun changement de configuration                     | Image non officielle : provenance et mises à jour de sécurité incertaines    |
| C. Adaptateur disque en CI            | Aucun service à lancer                                | Le chemin S3 de production ne serait plus testé                              |
| D. Émulateur GCS (`fake-gcs-server`)  | Proche de la cible                                    | API GCS native et non S3 : ce n'est pas le protocole qu'utilise l'adaptateur |

## Décision

**A.** Service `s3` dans `infra/docker/compose.dev.yml` et étape `docker run` dans
`.github/workflows/ci-backend.yml` (port hôte 9002, identifiants de dev `thy_s3`/`changeme123`).
Les buckets sont créés avec l'AWS CLI (`amazon/aws-cli`).

## Conséquences

- Les tests e2e tournent sur le stockage S3 ; l'adaptateur disque reste couvert par
  `backend/test/kernel/storage.e2e-spec.ts` (même contrat pour les deux adaptateurs).
- Client `@aws-sdk/client-s3` configuré avec `requestChecksumCalculation` et
  `responseChecksumValidation` à `"WHEN_REQUIRED"` : l'interop S3 de Cloud Storage ne connaît pas
  les sommes de contrôle CRC que le SDK ajoute par défaut depuis 2025.
- Règle retenue : vérifier qu'une image existe sur le registre public avant de l'adopter.
- **Non vérifié** : Cloud Storage réel n'a jamais été testé, faute de projet GCP.

## Remise en cause si

RustFS cesse d'être maintenu ou s'écarte du comportement S3 de Cloud Storage sur une opération
utilisée par l'adaptateur.
