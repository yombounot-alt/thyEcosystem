-- Ventes encaissées hors ligne : elles peuvent faire passer le stock sous zéro (les marchandises
-- sont déjà parties quand le serveur l'apprend). Le drapeau les rend visibles et auditables au lieu
-- d'être un simple contournement silencieux du contrôle de stock (audit du 2026-09-27).
ALTER TABLE biz.sales ADD COLUMN is_offline boolean NOT NULL DEFAULT false;
CREATE INDEX sales_offline_idx ON biz.sales (business_id, sold_at) WHERE is_offline;
