-- Extensions PostgreSQL requises par THY.
-- Référence : docs/blueprint/03-database.md §1.
-- postgis est déjà fournie par l'image postgis/postgis, mais l'activation explicite est idempotente.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
