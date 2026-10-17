-- Descriptions des schémas et des tables, lues par le générateur de docs/DATABASE.md
-- (backend/src/database/schema-doc-cli.ts). Aucun changement de structure.

COMMENT ON SCHEMA core IS 'Kernel : identité, entreprises (tenants), rôles et droits, staff.';
COMMENT ON SCHEMA ops IS 'Kernel : exploitation transverse (audit, outbox, idempotence, feature flags).';
COMMENT ON SCHEMA ntf IS 'Kernel : notifications (in-app et push).';
COMMENT ON SCHEMA sub IS 'Kernel : offres, abonnements et droits par entreprise.';
COMMENT ON SCHEMA biz IS 'Module Business (porté de thyBusiness) : catalogue, ventes, stock, clients, dépenses.';

-- core
COMMENT ON TABLE core.users IS 'Compte client, identifié par un numéro de téléphone vérifié (E.164).';
COMMENT ON TABLE core.otp_challenges IS 'Code de connexion envoyé par SMS : stocké haché, à durée de vie courte, tentatives limitées.';
COMMENT ON TABLE core.refresh_tokens IS 'Jeton de rafraîchissement opaque (haché) ; une famille par appareil, révoquée en bloc si un jeton est réutilisé.';
COMMENT ON TABLE core.login_events IS 'Historique des tentatives de connexion des clients (réussies ou non).';
COMMENT ON TABLE core.businesses IS 'Entreprise : le tenant. Toute donnée métier porte son business_id.';
COMMENT ON TABLE core.business_members IS 'Appartenance d''un utilisateur à une entreprise, avec son rôle.';
COMMENT ON TABLE core.business_invitations IS 'Invitation à rejoindre une entreprise, adressée à un numéro et acceptée dans l''app (pas de jeton dans un lien).';
COMMENT ON TABLE core.roles IS 'Rôle : de portée BUSINESS (propriétaire, gérant, caissier…) ou PLATFORM (staff THY).';
COMMENT ON TABLE core.permissions IS 'Catalogue des droits (codes stables, par exemple sales:create, admin:users.read).';
COMMENT ON TABLE core.role_permissions IS 'Droits accordés à chaque rôle.';
COMMENT ON TABLE core.staff_users IS 'Compte du staff THY pour la console d''administration (mot de passe argon2id, TOTP chiffré).';
COMMENT ON TABLE core.staff_role_assignments IS 'Rôles plateforme attribués à un membre du staff.';
COMMENT ON TABLE core.staff_sessions IS 'Session de la console d''administration (jeton et jeton anti-CSRF stockés hachés).';

-- ops
COMMENT ON TABLE ops.audit_logs IS 'Journal d''audit en ajout seul : qui (utilisateur, staff ou système) a fait quoi, sur quoi, et pourquoi.';
COMMENT ON TABLE ops.outbox_events IS 'Événements à publier, écrits dans la même transaction que le changement qui les produit.';
COMMENT ON TABLE ops.processed_events IS 'Événements déjà traités par chaque consommateur, pour un traitement idempotent.';
COMMENT ON TABLE ops.idempotency_keys IS 'Réponses mémorisées par clé d''idempotence, pour rejouer une requête sans effet double.';
COMMENT ON TABLE ops.feature_flags IS 'Fonctionnalités activables par part d''utilisateurs et par pays, gérées depuis l''admin.';

-- ntf
COMMENT ON TABLE ntf.notifications IS 'Notification destinée à un utilisateur (contenu et état de lecture).';
COMMENT ON TABLE ntf.notification_deliveries IS 'Tentative d''envoi d''une notification sur un canal (in-app, push).';
COMMENT ON TABLE ntf.notification_preferences IS 'Choix de l''utilisateur par type de notification et par canal.';
COMMENT ON TABLE ntf.device_tokens IS 'Jeton push d''un appareil, rattaché à l''utilisateur connecté sur cet appareil.';

-- sub
COMMENT ON TABLE sub.plans IS 'Offre commerciale (FREE, PRO…).';
COMMENT ON TABLE sub.entitlements IS 'Catalogue des droits d''offre : limites (LIMIT) ou fonctionnalités (BOOLEAN).';
COMMENT ON TABLE sub.plan_entitlements IS 'Valeur de chaque droit pour chaque offre (NULL = illimité).';
COMMENT ON TABLE sub.subscriptions IS 'Abonnement en cours d''une entreprise (une ligne par entreprise).';
COMMENT ON TABLE sub.subscription_events IS 'Historique en ajout seul de l''abonnement : début, changement d''offre, dérogations.';
COMMENT ON TABLE sub.entitlement_overrides IS 'Dérogation à la valeur de l''offre pour une entreprise, accordée depuis l''admin, avec motif et échéance facultative.';

-- biz
COMMENT ON TABLE biz.categories IS 'Catégorie de produits d''une entreprise.';
COMMENT ON TABLE biz.products IS 'Produit du catalogue : prix d''achat et de vente, stock courant, seuil d''alerte.';
COMMENT ON TABLE biz.inventory_movements IS 'Journal de stock en ajout seul : un mouvement ne se corrige que par un mouvement inverse.';
COMMENT ON TABLE biz.customers IS 'Client d''une entreprise (carnet de clients du commerçant).';
COMMENT ON TABLE biz.sales IS 'Vente encaissée ; is_offline signale une vente faite hors ligne, qui peut avoir fait passer le stock sous zéro.';
COMMENT ON TABLE biz.sale_items IS 'Ligne de vente : produit, quantité, prix appliqué.';
COMMENT ON TABLE biz.sale_counters IS 'Compteur par entreprise des numéros de vente, incrémenté de façon atomique (pas de doublon en concurrence).';
COMMENT ON TABLE biz.payments IS 'Encaissement rattaché à une vente, déclaré par le commerçant (espèces, mobile money…).';
COMMENT ON TABLE biz.customer_credits IS 'Crédit accordé à un client (vente à crédit) : montant initial, reste dû, échéance.';
COMMENT ON TABLE biz.credit_payments IS 'Remboursement d''un crédit client.';
COMMENT ON TABLE biz.expenses IS 'Dépense de l''entreprise.';
COMMENT ON TABLE biz.payment_methods IS 'Moyens de paiement direct du commerçant (Orange Money, Mobile Money, code marchand), affichés au client.';
COMMENT ON TABLE biz.manual_payments IS 'Paiement direct envoyé par un client sur un moyen du commerçant, déclaré avec référence ou preuve, puis confirmé ou refusé. Aucun prestataire de paiement.';

-- public
COMMENT ON TABLE public.schema_migrations IS 'Migrations appliquées, avec leur somme de contrôle (géré par le migrateur).';
