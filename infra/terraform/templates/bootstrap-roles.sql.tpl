-- Rendu par Terraform (voir main.tf, output `bootstrap_roles_sql`) — variante de
-- infra/docker/postgres/init/01-roles.sql pour Cloud SQL : mêmes rôles, mots de passe réels générés
-- par Terraform au lieu du "changeme" de développement local. À exécuter UNE FOIS, à la main, via le
-- proxy Cloud SQL Auth :
--
--   cloud-sql-proxy ${connection_name} &
--   PGPASSWORD='${migrator_password}' psql -h 127.0.0.1 -U ${migrator_user} -d ${database_name} \
--     -v ON_ERROR_STOP=1 -f bootstrap-roles.rendered.sql
--
-- Ce fichier contient des mots de passe : ne JAMAIS le committer (voir .gitignore).

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'thy_app') THEN
    CREATE ROLE thy_app LOGIN PASSWORD '${app_password}' NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'thy_readonly') THEN
    CREATE ROLE thy_readonly LOGIN PASSWORD '${readonly_password}' NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'thy_admin_app') THEN
    CREATE ROLE thy_admin_app LOGIN PASSWORD '${admin_app_password}' NOBYPASSRLS;
  END IF;
END
$$;

GRANT CONNECT ON DATABASE ${database_name} TO thy_app, thy_readonly, thy_admin_app;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Les GRANT par schéma/table restent accordés par les migrations applicatives elles-mêmes, comme en
-- local (voir infra/docker/postgres/init/01-roles.sql) : rien d'autre à faire ici.
