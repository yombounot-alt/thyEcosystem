-- Schéma `biz` — THY Business (portage de thyBusiness, base : arbre de travail du 2026-09-23).
-- Référence : docs/plans/consolidation-strategy.md §3.1, docs/blueprint/03-database.md §6.
--
-- Écarts assumés par rapport aux migrations Prisma d'origine :
--   * users / businesses / business_members / refresh_tokens / otp_verifications n'existent plus ici :
--     ils sont possédés par le kernel (schéma core). Les anciennes FK deviennent des FK vers core.*.
--   * identifiants en `uuid` (et non TEXT) pour s'aligner sur core.* ; types monétaires inchangés
--     (NUMERIC(14,2) — la conversion en unités mineures entières du blueprint, ADR-016, est un chantier
--     séparé qui touche aussi l'app mobile, voir docs/plans/consolidation-strategy.md).
--   * TOUTES les tables portent `business_id` + RLS (FORCE) : sale_items reçoit ce `business_id` qui
--     lui manquait, et les FK vers les tables parentes sont COMPOSITES (business_id, id) — impossible
--     de rattacher une ligne à la vente/au produit d'une autre entreprise, même par erreur de code.
--   * Prisma n'est utilisé que comme CLIENT de requêtes (backend/prisma/schema.prisma) : le DDL, les
--     politiques RLS et les index partiels vivent ici, dans le migrateur du kernel.

CREATE SCHEMA IF NOT EXISTS biz;
GRANT USAGE ON SCHEMA biz TO thy_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA biz GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO thy_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA biz GRANT USAGE, SELECT ON SEQUENCES TO thy_app;

-- Le coût d'un mouvement/une ligne se référence lui-même : voir contraintes ci-dessous.

CREATE TABLE biz.categories (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  name        text NOT NULL,
  created_at  timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (business_id, name),
  UNIQUE (business_id, id)
);
CREATE INDEX categories_business_idx ON biz.categories (business_id);

CREATE TABLE biz.products (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id         uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  category_id         uuid,
  name                text NOT NULL,
  sku                 text,
  barcode             text,
  unit                text NOT NULL DEFAULT 'unite',
  purchase_price      numeric(14,2) NOT NULL DEFAULT 0,
  sale_price          numeric(14,2) NOT NULL,
  current_stock       numeric(14,2) NOT NULL DEFAULT 0,
  low_stock_threshold numeric(14,2),
  is_active           boolean NOT NULL DEFAULT true,
  image_key           text,
  description         text,
  created_at          timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (business_id, id),
  FOREIGN KEY (business_id, category_id) REFERENCES biz.categories (business_id, id) ON DELETE SET NULL (category_id)
);
-- Unicité SKU / code-barres par entreprise. thyBusiness ne posait qu'un index NON unique alors que
-- ProductsService renvoie déjà « 409 : ce SKU ou ce code-barres existe déjà » : on aligne la base
-- sur l'intention du code (un scan de code-barres doit désigner UN produit).
CREATE UNIQUE INDEX products_business_sku_uq ON biz.products (business_id, sku) WHERE sku IS NOT NULL;
CREATE UNIQUE INDEX products_business_barcode_uq ON biz.products (business_id, barcode) WHERE barcode IS NOT NULL;
CREATE INDEX products_business_name_idx ON biz.products (business_id, name);
CREATE INDEX products_business_barcode_idx ON biz.products (business_id, barcode);

CREATE TABLE biz.customers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id     uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  full_name       text NOT NULL,
  phone           text,
  address         text,
  notes           text,
  current_balance numeric(14,2) NOT NULL DEFAULT 0,
  created_at      timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (business_id, id)
);
CREATE INDEX customers_business_name_idx ON biz.customers (business_id, full_name);
CREATE INDEX customers_business_phone_idx ON biz.customers (business_id, phone);

CREATE TABLE biz.sales (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id       uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  customer_id       uuid,
  sale_number       text NOT NULL,
  -- Clé générée par l'app : rejouer le même encaissement (retry réseau, double tap) renvoie la vente d'origine.
  client_request_id text,
  subtotal          numeric(14,2) NOT NULL,
  discount_total    numeric(14,2) NOT NULL DEFAULT 0,
  total             numeric(14,2) NOT NULL,
  amount_paid       numeric(14,2) NOT NULL DEFAULT 0,
  amount_due        numeric(14,2) NOT NULL DEFAULT 0,
  status            text NOT NULL DEFAULT 'completed',
  sold_by           uuid NOT NULL REFERENCES core.users (id),
  sold_at           timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at        timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (business_id, sale_number),
  UNIQUE (business_id, client_request_id),
  UNIQUE (business_id, id),
  FOREIGN KEY (business_id, customer_id) REFERENCES biz.customers (business_id, id) ON DELETE SET NULL (customer_id)
);
CREATE INDEX sales_business_sold_at_idx ON biz.sales (business_id, sold_at);

CREATE TABLE biz.sale_items (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id           uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  sale_id               uuid NOT NULL,
  product_id            uuid NOT NULL,
  product_name_snapshot text NOT NULL,
  unit_price            numeric(14,2) NOT NULL,
  unit_cost_snapshot    numeric(14,2) NOT NULL,
  quantity              numeric(14,2) NOT NULL,
  discount              numeric(14,2) NOT NULL DEFAULT 0,
  line_total            numeric(14,2) NOT NULL,
  FOREIGN KEY (business_id, sale_id) REFERENCES biz.sales (business_id, id) ON DELETE CASCADE,
  FOREIGN KEY (business_id, product_id) REFERENCES biz.products (business_id, id)
);
CREATE INDEX sale_items_sale_idx ON biz.sale_items (sale_id);

CREATE TABLE biz.payments (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id        uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  sale_id            uuid NOT NULL,
  method             text NOT NULL,
  amount             numeric(14,2) NOT NULL,
  received_by        uuid NOT NULL REFERENCES core.users (id),
  provider_reference text,
  received_at        timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at         timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (business_id, sale_id) REFERENCES biz.sales (business_id, id) ON DELETE CASCADE
);
CREATE INDEX payments_business_sale_idx ON biz.payments (business_id, sale_id);

CREATE TABLE biz.inventory_movements (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  product_id     uuid NOT NULL,
  type           text NOT NULL,
  quantity       numeric(14,2) NOT NULL,
  unit_cost      numeric(14,2),
  reference_type text,
  reference_id   text,
  note           text,
  created_by     uuid NOT NULL REFERENCES core.users (id),
  created_at     timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (business_id, product_id) REFERENCES biz.products (business_id, id)
);
CREATE INDEX inventory_movements_product_idx ON biz.inventory_movements (business_id, product_id, created_at);
-- Journal de stock append-only : un mouvement ne se corrige que par un mouvement inverse.
REVOKE UPDATE, DELETE ON biz.inventory_movements FROM thy_app;

CREATE TABLE biz.customer_credits (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id      uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  customer_id      uuid NOT NULL,
  sale_id          uuid,
  original_amount  numeric(14,2) NOT NULL,
  remaining_amount numeric(14,2) NOT NULL,
  status           text NOT NULL DEFAULT 'open',
  due_date         date,
  note             text,
  created_by       uuid NOT NULL REFERENCES core.users (id),
  created_at       timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (business_id, id),
  FOREIGN KEY (business_id, customer_id) REFERENCES biz.customers (business_id, id),
  FOREIGN KEY (business_id, sale_id) REFERENCES biz.sales (business_id, id) ON DELETE SET NULL (sale_id)
);
CREATE INDEX customer_credits_customer_idx ON biz.customer_credits (business_id, customer_id);
CREATE INDEX customer_credits_status_idx ON biz.customer_credits (business_id, status);

CREATE TABLE biz.credit_payments (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id        uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  customer_id        uuid NOT NULL,
  customer_credit_id uuid NOT NULL,
  amount             numeric(14,2) NOT NULL,
  method             text NOT NULL,
  received_by        uuid NOT NULL REFERENCES core.users (id),
  note               text,
  paid_at            timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at         timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (business_id, customer_id) REFERENCES biz.customers (business_id, id),
  FOREIGN KEY (business_id, customer_credit_id) REFERENCES biz.customer_credits (business_id, id)
);
CREATE INDEX credit_payments_customer_idx ON biz.credit_payments (business_id, customer_id);

CREATE TABLE biz.expenses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id  uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  category     text NOT NULL,
  amount       numeric(14,2) NOT NULL,
  description  text,
  expense_date date NOT NULL DEFAULT CURRENT_DATE,
  recorded_by  uuid NOT NULL REFERENCES core.users (id),
  created_at   timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX expenses_business_date_idx ON biz.expenses (business_id, expense_date);

-- Paiements directs (Orange Money, Mobile Money, code marchand) — ADR 0011 de thyBusiness.
CREATE TABLE biz.payment_methods (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  provider      text NOT NULL,
  display_name  text NOT NULL,
  account_name  text,
  phone_number  text,
  merchant_code text,
  instructions  text,
  ussd_code     text,
  logo_key      text,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (business_id, id)
);
CREATE INDEX payment_methods_active_idx ON biz.payment_methods (business_id, is_active);

CREATE TABLE biz.manual_payments (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id           uuid NOT NULL REFERENCES core.businesses (id) ON DELETE CASCADE,
  created_by            uuid NOT NULL REFERENCES core.users (id),
  payment_method_id     uuid,
  method_provider       text NOT NULL,
  method_name           text NOT NULL,
  sent_to_holder        text,
  sent_to_phone         text,
  sent_to_code          text,
  client_request_id     text NOT NULL,
  amount                numeric(14,2) NOT NULL,
  currency              text NOT NULL DEFAULT 'GNF',
  status                text NOT NULL DEFAULT 'pending',
  checkout              jsonb NOT NULL,
  sale_id               uuid,
  payer_name            text,
  payer_phone           text,
  transaction_reference text,
  reference_key         text,
  amount_sent           numeric(14,2),
  paid_at               timestamp(3),
  proof_key             text,
  submitted_at          timestamp(3),
  verified_at           timestamp(3),
  verified_by           uuid REFERENCES core.users (id) ON DELETE SET NULL,
  rejected_at           timestamp(3),
  rejected_by           uuid REFERENCES core.users (id) ON DELETE SET NULL,
  rejection_reason      text,
  cancelled_at          timestamp(3),
  created_at            timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (business_id, client_request_id),
  UNIQUE (sale_id),
  FOREIGN KEY (business_id, payment_method_id) REFERENCES biz.payment_methods (business_id, id) ON DELETE SET NULL (payment_method_id),
  FOREIGN KEY (business_id, sale_id) REFERENCES biz.sales (business_id, id) ON DELETE SET NULL (sale_id)
);
CREATE INDEX manual_payments_status_idx ON biz.manual_payments (business_id, status, created_at);
-- Une référence de transaction ne prouve qu'UN paiement (garanti par la base, pas seulement par le code).
CREATE UNIQUE INDEX manual_payments_reference_in_use_key
  ON biz.manual_payments (business_id, method_provider, reference_key)
  WHERE reference_key IS NOT NULL AND status IN ('submitted', 'verified');

-- updated_at : Prisma le pose côté client (@updatedAt) ; ce trigger le garantit aussi pour tout autre accès.
CREATE OR REPLACE FUNCTION biz.touch_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['categories','products','customers','sales','customer_credits','expenses','payment_methods','manual_payments']
  LOOP
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON biz.%I FOR EACH ROW EXECUTE FUNCTION biz.touch_updated_at()', t || '_touch', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Row-Level Security : chaque table est cloisonnée par entreprise (fail-closed).
-- Contexte posé par BizPrisma.run() → `SELECT set_config('app.business_id', …, true)`.
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['categories','products','customers','sales','sale_items','payments','inventory_movements',
                           'customer_credits','credit_payments','expenses','payment_methods','manual_payments']
  LOOP
    EXECUTE format('ALTER TABLE biz.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE biz.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON biz.%I
      USING (business_id = NULLIF(current_setting('app.business_id', true), '')::uuid)
      WITH CHECK (business_id = NULLIF(current_setting('app.business_id', true), '')::uuid)$p$, t);
  END LOOP;
END $$;
