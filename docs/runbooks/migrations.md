# Runbook — migrations de base

Contexte : [ADR-003](../adr/0003-acces-aux-donnees-et-migrations.md) et
[ADR-018](../adr/0018-decouverte-de-code-existant-strategie-de-consolidation.md). Toutes les
migrations, quel que soit le schéma, sont des fichiers SQL écrits à la main dans
`backend/migrations/`. Le migrateur du kernel les applique. Aucun ORM ne crée de schéma (pas de
`prisma migrate`).

## Écrire une migration

1. Nouveau fichier `backend/migrations/NNNN_description.sql`, avec le numéro suivant.
2. Toute nouvelle table métier :
   - porte `business_id` ;
   - a `ENABLE` + `FORCE ROW LEVEL SECURITY` et une politique sur `app.business_id` ;
   - a des clés étrangères composites `(business_id, id)` ;
   - reçoit des `GRANT` explicites pour `thy_app`, et pour `thy_admin_app` s'il en a besoin ;
   - a un `COMMENT ON TABLE`.
3. Si le module Business est touché, mettre à jour `backend/prisma/schema.prisma` : le test
   `schema-drift` le compare à la base.
4. Appliquer et régénérer la documentation :

   ```bash
   cd backend && npx nest build
   node --env-file=.env dist/database/migrate-cli.js
   node --env-file=.env dist/database/schema-doc-cli.js   # met à jour docs/DATABASE.md
   ```

5. Commiter la migration **et** `docs/DATABASE.md` ensemble. La CI échoue sinon.

## Règles

- **Une migration appliquée ne se modifie jamais.** Le migrateur enregistre une somme de contrôle
  par fichier et refuse de continuer si elle a changé. Pour corriger, écrire une nouvelle migration.
- Forward-only : pas de migration « down ». Une colonne se retire en deux temps (expand/contract) :
  d'abord le code cesse de l'utiliser et la version est déployée, puis une migration la supprime.
- Le migrateur pose un verrou consultatif : deux exécutions simultanées ne se marchent pas dessus.

## Appliquer

- **Local** : la commande ci-dessus, ou démarrer l'API avec `backend/.env`, qui fournit `MIGRATOR_DATABASE_URL` (en développement seulement). Les tests e2e ne les appliquent pas eux-mêmes.
- **Réinitialiser la base locale** : `./infra/scripts/dev-reset-db.ps1` détruit les données de dev.
- **GCP** : `gcloud run jobs execute <prefixe>-migrate --region europe-west1 --wait`, **avant** de
  déployer la version de l'API qui en dépend.

## Somme de contrôle refusée

Cela signifie qu'un fichier déjà appliqué a été modifié.

- En local seulement, si la modification n'a jamais été poussée : restaurer le fichier
  (`git checkout -- backend/migrations/<fichier>`) et écrire une nouvelle migration, ou
  réinitialiser la base de dev.
- Sur un environnement partagé : **ne jamais** modifier `schema_migrations` à la main. Restaurer le
  fichier d'origine et corriger par une nouvelle migration.
