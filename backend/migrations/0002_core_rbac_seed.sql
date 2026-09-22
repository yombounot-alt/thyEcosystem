-- Données de référence RBAC : permissions, rôles système BUSINESS et leur matrice par défaut.
-- Référence : docs/blueprint/04-identity-access.md §4.2–4.3. Idempotent (ON CONFLICT DO NOTHING) :
-- rejouable en production comme n'importe quel seed de référence (docs/blueprint/03-database.md §9).
--
-- Portée volontairement limitée à ce que la Phase 0 exerce réellement (adhésion, rôle des membres) ;
-- les permissions des modules métier (sales:*, inventory:*, …) sont créées ici par anticipation car
-- elles font déjà partie du rôle système décrit dans le blueprint — le portage de thyBusiness (Phase 1)
-- les consommera directement plutôt que d'en redéfinir un second jeu.

INSERT INTO core.permissions (code, description) VALUES
  ('sales:create',        'Encaisser une vente'),
  ('sales:refund',        'Rembourser ou annuler une vente'),
  ('products:manage',     'Créer ou modifier les produits et catégories'),
  ('inventory:adjust',    'Ajuster le stock (entrées, sorties, inventaire)'),
  ('purchases:manage',    'Gérer les achats et fournisseurs'),
  ('credits:manage',      'Gérer les crédits clients (créances)'),
  ('expenses:manage',     'Saisir et gérer les dépenses'),
  ('finance:view_profit', 'Voir les coûts, marges et bénéfices'),
  ('reports:view',        'Consulter les rapports'),
  ('members:manage',      'Inviter, modifier ou retirer des membres et leurs rôles'),
  ('subscription:manage', 'Gérer l''abonnement et le paiement de l''entreprise'),
  ('marketplace:publish', 'Publier un produit sur THY Marketplace')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.roles (code, scope, business_id, is_system) VALUES
  ('OWNER',        'BUSINESS', NULL, true),
  ('ADMIN',        'BUSINESS', NULL, true),
  ('MANAGER',      'BUSINESS', NULL, true),
  ('CASHIER',      'BUSINESS', NULL, true),
  ('STOCK_KEEPER', 'BUSINESS', NULL, true),
  ('ACCOUNTANT',   'BUSINESS', NULL, true),
  ('VIEWER',       'BUSINESS', NULL, true)
ON CONFLICT (scope, code) WHERE business_id IS NULL DO NOTHING;

-- Matrice par défaut (docs/blueprint/04-identity-access.md §4.3, cases ⚠️ non accordées par défaut).
INSERT INTO core.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM (VALUES
  ('OWNER',        'sales:create'),        ('OWNER',        'sales:refund'),
  ('OWNER',        'products:manage'),     ('OWNER',        'inventory:adjust'),
  ('OWNER',        'purchases:manage'),    ('OWNER',        'credits:manage'),
  ('OWNER',        'expenses:manage'),     ('OWNER',        'finance:view_profit'),
  ('OWNER',        'reports:view'),        ('OWNER',        'members:manage'),
  ('OWNER',        'subscription:manage'), ('OWNER',        'marketplace:publish'),

  ('ADMIN',        'sales:create'),        ('ADMIN',        'sales:refund'),
  ('ADMIN',        'products:manage'),     ('ADMIN',        'inventory:adjust'),
  ('ADMIN',        'purchases:manage'),    ('ADMIN',        'credits:manage'),
  ('ADMIN',        'expenses:manage'),     ('ADMIN',        'finance:view_profit'),
  ('ADMIN',        'reports:view'),        ('ADMIN',        'members:manage'),
  ('ADMIN',        'marketplace:publish'),

  ('MANAGER',      'sales:create'),        ('MANAGER',      'sales:refund'),
  ('MANAGER',      'products:manage'),     ('MANAGER',      'inventory:adjust'),
  ('MANAGER',      'purchases:manage'),    ('MANAGER',      'credits:manage'),
  ('MANAGER',      'expenses:manage'),     ('MANAGER',      'reports:view'),
  ('MANAGER',      'marketplace:publish'),

  ('CASHIER',      'sales:create'),        ('CASHIER',      'credits:manage'),

  ('STOCK_KEEPER', 'products:manage'),     ('STOCK_KEEPER', 'inventory:adjust'),
  ('STOCK_KEEPER', 'purchases:manage'),

  ('ACCOUNTANT',   'purchases:manage'),    ('ACCOUNTANT',   'credits:manage'),
  ('ACCOUNTANT',   'expenses:manage'),     ('ACCOUNTANT',   'finance:view_profit'),
  ('ACCOUNTANT',   'reports:view'),

  ('VIEWER',       'reports:view')
) AS matrix(role_code, permission_code)
JOIN core.roles r ON r.code = matrix.role_code AND r.scope = 'BUSINESS' AND r.business_id IS NULL
JOIN core.permissions p ON p.code = matrix.permission_code
ON CONFLICT (role_id, permission_id) DO NOTHING;
