-- Rôles applicatifs PostgreSQL pour THY (dev local).
-- Référence : docs/blueprint/03-database.md §1 (Rôles DB).
-- thy_migrator (défini par POSTGRES_USER/PASSWORD du service, propriétaire du schéma, exécute les
-- migrations) existe déjà. Ce script crée les rôles d'exécution applicative et de lecture seule,
-- SANS droit de contournement de la sécurité au niveau ligne (RLS) : c'est ce qui rend le
-- multi-tenant fiable (voir 03-database.md §6, ADR-004).

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'thy_app') THEN
    CREATE ROLE thy_app LOGIN PASSWORD 'changeme' NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'thy_readonly') THEN
    CREATE ROLE thy_readonly LOGIN PASSWORD 'changeme' NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'thy_admin_app') THEN
    CREATE ROLE thy_admin_app LOGIN PASSWORD 'changeme' NOBYPASSRLS;
  END IF;
END
$$;

GRANT CONNECT ON DATABASE thy TO thy_app, thy_readonly, thy_admin_app;

-- Les GRANT par schéma/table sont accordés par les migrations elles-mêmes au fil de leur création
-- (chaque migration de module accorde les droits sur SES tables aux rôles applicatifs). Rien à
-- faire ici tant qu'aucun schéma métier n'existe (Phase 0, lot L0.5+).
