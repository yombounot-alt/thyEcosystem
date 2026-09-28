/**
 * Registre des types de notification : gabarits (fr/en), canaux par défaut, et si l'utilisateur
 * peut les couper. Référence : docs/blueprint/06-platform-engines.md §2 (« les notifications de
 * sécurité ne sont pas désactivables »).
 *
 * Les textes sont rendus à la CRÉATION, dans la langue de l'utilisateur à ce moment-là : une
 * notification est un fait historique, pas une vue.
 */
export type Channel = "IN_APP" | "PUSH";
export type Locale = "fr" | "en";

export interface NotificationTemplate {
  channels: readonly Channel[];
  /** false : l'utilisateur ne peut pas la couper (sécurité). */
  optional: boolean;
  render(locale: Locale, data: Record<string, string>): { title: string; body: string };
}

const ROLE_LABELS: Record<Locale, Record<string, string>> = {
  fr: {
    OWNER: "propriétaire",
    ADMIN: "administrateur",
    MANAGER: "gérant",
    CASHIER: "caissier",
    STOCK_KEEPER: "magasinier",
    ACCOUNTANT: "comptable",
    VIEWER: "lecteur",
  },
  en: {
    OWNER: "owner",
    ADMIN: "administrator",
    MANAGER: "manager",
    CASHIER: "cashier",
    STOCK_KEEPER: "stock keeper",
    ACCOUNTANT: "accountant",
    VIEWER: "viewer",
  },
};
export const roleLabel = (locale: Locale, code: string) => ROLE_LABELS[locale][code] ?? code;

const t =
  (fr: [string, string], en: [string, string]) =>
  (locale: Locale, data: Record<string, string>) => {
    const [title, body] = locale === "en" ? en : fr;
    // {roleLabel} se traduit depuis data.roleCode, dans la langue du destinataire.
    const value = (k: string) =>
      k === "roleLabel" ? roleLabel(locale, data.roleCode ?? "") : (data[k] ?? "");
    const fill = (s: string) => s.replace(/\{(\w+)\}/g, (_, k: string) => value(k));
    return { title: fill(title), body: fill(body) };
  };

export const NOTIFICATION_TYPES = {
  BUSINESS_WELCOME: {
    channels: ["IN_APP", "PUSH"],
    optional: true,
    render: t(
      [
        "Bienvenue sur THY",
        "« {businessName} » est prête. Ajoutez vos produits pour commencer à vendre.",
      ],
      ["Welcome to THY", "“{businessName}” is ready. Add your products to start selling."],
    ),
  },
  MEMBER_JOINED: {
    channels: ["IN_APP", "PUSH"],
    optional: true,
    render: t(
      ["Vous avez rejoint {businessName}", "Votre rôle : {roleLabel}."],
      ["You joined {businessName}", "Your role: {roleLabel}."],
    ),
  },
  TEAM_MEMBER_JOINED: {
    channels: ["IN_APP", "PUSH"],
    optional: true,
    render: t(
      ["Nouveau membre", "{memberName} a rejoint {businessName} ({roleLabel})."],
      ["New team member", "{memberName} joined {businessName} ({roleLabel})."],
    ),
  },
  MEMBER_ROLE_CHANGED: {
    channels: ["IN_APP", "PUSH"],
    optional: false,
    render: t(
      ["Votre rôle a changé", "Vous êtes maintenant {roleLabel} dans {businessName}."],
      ["Your role changed", "You are now {roleLabel} in {businessName}."],
    ),
  },
  MEMBER_PERMISSIONS_CHANGED: {
    channels: ["IN_APP"],
    optional: false,
    render: t(
      ["Vos droits ont changé", "Vos autorisations dans {businessName} ont été modifiées."],
      ["Your permissions changed", "Your permissions in {businessName} were updated."],
    ),
  },
  MEMBER_REMOVED: {
    channels: ["IN_APP", "PUSH"],
    optional: false,
    render: t(
      ["Accès retiré", "Vous n'avez plus accès à {businessName}."],
      ["Access removed", "You no longer have access to {businessName}."],
    ),
  },
  BUSINESS_INVITATION: {
    channels: ["IN_APP", "PUSH"],
    optional: false,
    render: t(
      ["Invitation reçue", "{businessName} vous invite à rejoindre l'équipe ({roleLabel})."],
      ["Invitation received", "{businessName} invites you to join the team ({roleLabel})."],
    ),
  },
  STOCK_LOW: {
    channels: ["IN_APP", "PUSH"],
    optional: true,
    render: t(
      ["Stock bas : {productName}", "Il reste {stock} en stock (seuil d'alerte : {threshold})."],
      ["Low stock: {productName}", "{stock} left in stock (alert threshold: {threshold})."],
    ),
  },
  STOCK_NEGATIVE: {
    channels: ["IN_APP", "PUSH"],
    optional: true,
    render: t(
      [
        "Stock négatif : {productName}",
        "Une vente hors ligne a fait passer le stock à {stock}. Vérifiez le stock réel et faites un ajustement.",
      ],
      [
        "Negative stock: {productName}",
        "An offline sale brought stock down to {stock}. Check the real stock and adjust it.",
      ],
    ),
  },
  SECURITY_SESSION_REVOKED: {
    channels: ["IN_APP", "PUSH"],
    optional: false,
    render: t(
      [
        "Alerte de sécurité",
        "Une ancienne session a été réutilisée : par précaution, elle a été fermée. Reconnectez-vous si besoin.",
      ],
      [
        "Security alert",
        "An old session was reused: as a precaution it was closed. Sign in again if needed.",
      ],
    ),
  },
} as const satisfies Record<string, NotificationTemplate>;

export type NotificationType = keyof typeof NOTIFICATION_TYPES;

export const isNotificationType = (v: string): v is NotificationType =>
  Object.hasOwn(NOTIFICATION_TYPES, v);
