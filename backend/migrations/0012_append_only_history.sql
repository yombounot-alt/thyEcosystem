-- Les tables d'historique sont en ajout seul, mais `thy_app` gardait UPDATE et DELETE dessus
-- (droits par défaut du schéma) : une injection SQL ou un bug de l'API pouvait réécrire ou effacer
-- des traces. Relevé en générant docs/DATABASE.md (lot L0.12). Même règle que
-- biz.inventory_movements (migration 0004). Aucun code de l'API ne modifie ces lignes.
REVOKE UPDATE, DELETE, TRUNCATE ON ops.audit_logs FROM thy_app;
REVOKE UPDATE, DELETE, TRUNCATE ON sub.subscription_events FROM thy_app;
REVOKE UPDATE, DELETE, TRUNCATE ON core.login_events FROM thy_app;
