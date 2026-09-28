-- Numérotation des ventes sans collision. Avant : `count(*) + 1` recalculé à chaque encaissement,
-- donc deux caisses simultanées obtenaient le même numéro et l'une des ventes échouait (409) une
-- fois ses essais épuisés. Désormais un compteur par entreprise, incrémenté par un UPSERT dont le
-- verrou de ligne sérialise les encaissements concurrents d'une même entreprise jusqu'au COMMIT
-- (un numéro n'est donc jamais « perdu » : un ROLLBACK annule aussi l'incrément).
CREATE TABLE biz.sale_counters (
  business_id uuid PRIMARY KEY REFERENCES core.businesses (id) ON DELETE CASCADE,
  last_number integer NOT NULL CHECK (last_number >= 0)
);

-- Reprise de l'existant : le plus grand numéro déjà attribué (format VTE-0001), à défaut le nombre de ventes.
INSERT INTO biz.sale_counters (business_id, last_number)
SELECT business_id,
       GREATEST(count(*), COALESCE(max(NULLIF(substring(sale_number FROM '^VTE-(\d+)$'), '')::int), 0))
  FROM biz.sales
 GROUP BY business_id;

ALTER TABLE biz.sale_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE biz.sale_counters FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON biz.sale_counters
  USING (business_id = NULLIF(current_setting('app.business_id', true), '')::uuid)
  WITH CHECK (business_id = NULLIF(current_setting('app.business_id', true), '')::uuid);
