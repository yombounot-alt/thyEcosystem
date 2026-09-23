-- Permissions supplémentaires requises par THY Business + surcharges de permissions par membre.
-- Origine : portage de thyBusiness (voir docs/plans/consolidation-strategy.md §3.1) — son RBAC
-- multi-employés (rôle + surcharges individuelles « configurables individuellement », cahier des
-- charges écran 23) est repris ICI, dans le kernel, pour rester commun à tous les modules.
--
-- Table de correspondance thyBusiness → kernel (les codes du kernel utilisent « : ») :
--   sales.create → sales:create            sales.void → sales:refund
--   products.write → products:manage       inventory.write → inventory:adjust
--   customers.write → customers:manage     credits.manage → credits:manage
--   expenses.write → expenses:manage       payment_methods.manage → payment_methods:manage
--   payments.verify → payments:verify      business.settings.write → business:settings
--   employees.manage → members:manage (jamais surchargeable)

ALTER TABLE core.business_members
  ADD COLUMN permission_overrides jsonb;
COMMENT ON COLUMN core.business_members.permission_overrides IS
  'Écarts par rapport aux permissions par défaut du rôle : {"sales:refund": true, "credits:manage": false}. members:manage et subscription:manage ne sont jamais surchargeables.';

INSERT INTO core.permissions (code, description) VALUES
  ('catalog:view',           'Consulter produits et catégories'),
  ('inventory:view',         'Consulter les mouvements de stock'),
  ('sales:view',             'Consulter les ventes et reçus'),
  ('customers:view',         'Consulter les clients et leurs crédits'),
  ('customers:manage',       'Créer, modifier ou supprimer des clients'),
  ('expenses:view',          'Consulter les dépenses'),
  ('payments:view',          'Consulter les paiements mobile money déclarés'),
  ('payments:declare',       'Démarrer et déclarer un paiement mobile money (caisse)'),
  ('payments:verify',        'Valider, refuser ou annuler un paiement déclaré'),
  ('payment_methods:manage', 'Configurer les moyens de paiement de l''entreprise'),
  ('business:settings',      'Modifier les paramètres de l''entreprise')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM (VALUES
  -- Lecture catalogue : tous les rôles (la caisse en a besoin, y compris le caissier).
  ('OWNER','catalog:view'),('ADMIN','catalog:view'),('MANAGER','catalog:view'),('CASHIER','catalog:view'),
  ('STOCK_KEEPER','catalog:view'),('ACCOUNTANT','catalog:view'),('VIEWER','catalog:view'),

  ('OWNER','inventory:view'),('ADMIN','inventory:view'),('MANAGER','inventory:view'),
  ('STOCK_KEEPER','inventory:view'),('ACCOUNTANT','inventory:view'),('VIEWER','inventory:view'),

  ('OWNER','sales:view'),('ADMIN','sales:view'),('MANAGER','sales:view'),('CASHIER','sales:view'),
  ('ACCOUNTANT','sales:view'),('VIEWER','sales:view'),

  ('OWNER','customers:view'),('ADMIN','customers:view'),('MANAGER','customers:view'),('CASHIER','customers:view'),
  ('ACCOUNTANT','customers:view'),('VIEWER','customers:view'),

  ('OWNER','customers:manage'),('ADMIN','customers:manage'),('MANAGER','customers:manage'),('CASHIER','customers:manage'),

  ('OWNER','expenses:view'),('ADMIN','expenses:view'),('MANAGER','expenses:view'),
  ('ACCOUNTANT','expenses:view'),('VIEWER','expenses:view'),

  ('OWNER','payments:view'),('ADMIN','payments:view'),('MANAGER','payments:view'),
  ('CASHIER','payments:view'),('ACCOUNTANT','payments:view'),

  ('OWNER','payments:declare'),('ADMIN','payments:declare'),('MANAGER','payments:declare'),('CASHIER','payments:declare'),

  -- Comme dans le RBAC en cours de thyBusiness : le gérant valide les paiements et règle les moyens de paiement.
  ('OWNER','payments:verify'),('ADMIN','payments:verify'),('MANAGER','payments:verify'),
  ('OWNER','payment_methods:manage'),('ADMIN','payment_methods:manage'),('MANAGER','payment_methods:manage'),
  ('OWNER','business:settings'),('ADMIN','business:settings'),('MANAGER','business:settings')
) AS matrix(role_code, permission_code)
JOIN core.roles r ON r.code = matrix.role_code AND r.scope = 'BUSINESS' AND r.business_id IS NULL
JOIN core.permissions p ON p.code = matrix.permission_code
ON CONFLICT (role_id, permission_id) DO NOTHING;
