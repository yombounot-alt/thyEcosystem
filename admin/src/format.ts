const dateTime = new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" });
const dateOnly = new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium" });

export function formatDateTime(value: string | null | undefined): string {
  return value ? dateTime.format(new Date(value)) : "—";
}

export function formatDate(value: string | null | undefined): string {
  return value ? dateOnly.format(new Date(value)) : "—";
}

export const ROLE_LABELS: Record<string, string> = {
  SUPER_ADMIN: "Super-administrateur",
  ADMIN: "Administrateur",
  SUPPORT_AGENT: "Agent support",
  OWNER: "Propriétaire",
  MANAGER: "Gérant",
  CASHIER: "Caissier",
};

export const USER_STATUS_LABELS: Record<string, string> = {
  ACTIVE: "Actif",
  SUSPENDED: "Suspendu",
  BANNED: "Banni",
  DELETED: "Supprimé",
};

export const SUBSCRIPTION_STATUS_LABELS: Record<string, string> = {
  TRIALING: "essai",
  ACTIVE: "active",
  PAST_DUE: "paiement en retard",
  GRACE: "période de grâce",
  EXPIRED: "expirée",
  CANCELED: "résiliée",
};

/** Libellés des actions d'audit connues ; les autres s'affichent telles quelles. */
export const AUDIT_ACTION_LABELS: Record<string, string> = {
  "staff.created": "Compte staff créé",
  "staff.login": "Connexion staff",
  "staff.login_failed": "Échec de connexion staff",
  "staff.locked": "Compte staff verrouillé",
  "staff.totp_enabled": "Double authentification activée",
  "staff.logout": "Déconnexion staff",
  "admin.user.reveal_phone": "Numéro affiché en clair",
  "admin.user.suspend": "Utilisateur suspendu",
  "admin.user.reactivate": "Utilisateur réactivé",
  "admin.user.revoke_sessions": "Sessions révoquées",
  "admin.flag.update": "Flag modifié",
  "business.create": "Entreprise créée",
  "business.update": "Entreprise modifiée",
  "admin.entitlement.override": "Dérogation d'offre définie",
  "admin.entitlement.override_removed": "Dérogation d'offre retirée",
};

export function label(map: Record<string, string>, key: string | null | undefined): string {
  if (!key) return "—";
  return map[key] ?? key;
}

/** Valeur d'un droit d'offre : `null` = illimité ; un droit BOOLEAN vaut 0 ou 1. */
export function entitlementValue(kind: string, value: number | null): string {
  if (kind === "BOOLEAN") return value ? "Oui" : "Non";
  return value === null ? "Illimité" : String(value);
}
