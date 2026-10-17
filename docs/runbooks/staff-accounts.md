# Runbook — comptes du staff (console d'administration)

Contexte : [ADR-020](../adr/0020-authentification-du-staff-comptes-thy-et-totp.md). Il n'existe
**aucun compte par défaut**. Un compte se crée en ligne de commande, avec la connexion du migrateur :
le rôle de l'API admin n'a pas le droit de créer des comptes staff.

## Créer un compte (dont le premier super-administrateur)

Prérequis : accès à la base avec `thy_migrator` (en local : `backend/.env` ; sur GCP : via
`cloud-sql-proxy` et le secret `…-migrator-database-url`), et un backend compilé.

```bash
cd backend
npx nest build
node --env-file=.env dist/modules/admin/staff-cli.js \
  --email awa@thy.gn --name "Awa Camara" --role SUPER_ADMIN
```

- Rôles : `SUPER_ADMIN`, `ADMIN`, `SUPPORT_AGENT` (par défaut). Le détail des droits est dans la
  migration `0010_admin.sql`.
- Le mot de passe est **généré et affiché une seule fois**. Le transmettre à la personne par un
  canal sûr (gestionnaire de mots de passe partagé), jamais par SMS ou e-mail en clair. Ne pas
  coller la sortie dans un ticket ni dans un journal.
- À la première connexion, la console impose l'enrôlement d'une application d'authentification.
- La création est inscrite au journal d'audit (`staff.created`, auteur `system`).

## Compte verrouillé

Après 5 échecs (mot de passe ou code), le compte est verrouillé 15 minutes, et la réponse est
`423 STAFF_LOCKED`. **Attendre** : le verrou se lève seul. Des verrouillages répétés sur un même
compte sont un signal d'attaque : vérifier le journal d'audit (`staff.login_failed`,
`staff.locked`).

## Désactiver un compte (départ, téléphone perdu)

Il n'y a pas encore de CLI pour cette opération. Avec `thy_migrator` :

```sql
BEGIN;
UPDATE core.staff_users SET status = 'SUSPENDED' WHERE email = 'awa@thy.gn';
UPDATE core.staff_sessions SET revoked_at = now()
 WHERE revoked_at IS NULL AND staff_id = (SELECT id FROM core.staff_users WHERE email = 'awa@thy.gn');
INSERT INTO ops.audit_logs (actor_id, actor_type, action, target_type, target_id, metadata)
SELECT NULL, 'system', 'staff.suspended', 'staff', id::text, '{"reason": "<motif>", "via": "runbook"}'
  FROM core.staff_users WHERE email = 'awa@thy.gn';
COMMIT;
```

Un compte suspendu est refusé dès sa requête suivante, même avec une session ouverte.

## Réinitialiser la double authentification (téléphone perdu, compte conservé)

```sql
UPDATE core.staff_users
   SET totp_secret_enc = NULL, totp_enabled_at = NULL, totp_last_step = NULL
 WHERE email = 'awa@thy.gn';
```

Révoquer aussi ses sessions (requête ci-dessus), puis inscrire l'opération au journal d'audit. À la
connexion suivante, la console redemande l'enrôlement.
