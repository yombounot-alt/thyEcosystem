// Crée un compte staff (outil d'exploitation, docs/blueprint/09-admin.md). Aucun compte ni
// identifiant par défaut n'existe : le premier SUPER_ADMIN se crée ainsi, par un opérateur qui a la
// connexion du migrateur (le rôle de l'API admin n'a pas le droit de créer des comptes staff).
//
//   pnpm --filter @thy/backend run staff:create -- --email awa@thy.gn --name "Awa Camara" --role SUPER_ADMIN
//
// Le mot de passe est généré (fort, aléatoire) et affiché UNE seule fois ; la double
// authentification (TOTP) est exigée à la première connexion.
import { randomBytes } from "node:crypto";
import { parseArgs } from "node:util";
import pg from "pg";
import { loadConfig, requireMigratorUrl } from "../../kernel/config/config.js";
import { CryptoService } from "../../kernel/security/crypto.service.js";

const { values } = parseArgs({
  options: {
    email: { type: "string" },
    name: { type: "string" },
    role: { type: "string", default: "SUPPORT_AGENT" },
  },
});

const email = values.email?.trim().toLowerCase();
const name = values.name?.trim();
if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || !name) {
  process.stderr.write(
    "Usage : staff:create --email <e-mail> --name <nom complet> [--role SUPER_ADMIN|ADMIN|SUPPORT_AGENT]\n",
  );
  process.exit(2);
}

const cfg = loadConfig();
const crypto = new CryptoService(cfg);
// 24 caractères base64url (~144 bits) : à conserver dans un gestionnaire de mots de passe.
const password = randomBytes(18).toString("base64url");

const client = new pg.Client({ connectionString: requireMigratorUrl(cfg) });
await client.connect();
try {
  await client.query("BEGIN");
  const role = await client.query<{ id: string }>(
    "SELECT id FROM core.roles WHERE scope = 'PLATFORM' AND code = $1 AND business_id IS NULL",
    [values.role],
  );
  const roleId = role.rows[0]?.id;
  if (!roleId) throw new Error(`Rôle plateforme inconnu : ${values.role}`);
  const inserted = await client.query<{ id: string }>(
    `INSERT INTO core.staff_users (email, password_hash, full_name) VALUES ($1, $2, $3)
     ON CONFLICT (email) DO NOTHING RETURNING id`,
    [email, await crypto.hashPassword(password), name],
  );
  const staffId = inserted.rows[0]?.id;
  if (!staffId) throw new Error(`Un compte staff existe déjà pour ${email}`);
  await client.query(
    "INSERT INTO core.staff_role_assignments (staff_id, role_id) VALUES ($1, $2)",
    [staffId, roleId],
  );
  await client.query(
    `INSERT INTO ops.audit_logs (actor_id, actor_type, action, target_type, target_id, metadata)
     VALUES (NULL, 'system', 'staff.created', 'staff', $1, $2)`,
    [staffId, JSON.stringify({ role: values.role, via: "staff-cli" })],
  );
  await client.query("COMMIT");
  process.stdout.write(
    `Compte staff créé : ${email} (${values.role})\n` +
      `Mot de passe (affiché une seule fois) : ${password}\n` +
      "La double authentification sera demandée à la première connexion.\n",
  );
} catch (error) {
  await client.query("ROLLBACK").catch(() => undefined);
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
} finally {
  await client.end();
}
