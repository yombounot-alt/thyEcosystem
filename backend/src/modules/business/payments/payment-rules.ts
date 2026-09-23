/** The ways a customer can pay the owner directly. "other" is for any wallet the owner adds. */
export const PAYMENT_PROVIDERS = [
  "orange_money",
  "mobile_money",
  "merchant_code",
  "other",
] as const;
export type PaymentProvider = (typeof PAYMENT_PROVIDERS)[number];

export const PROVIDER_LABEL: Record<PaymentProvider, string> = {
  orange_money: "Orange Money",
  mobile_money: "Mobile Money",
  merchant_code: "Code marchand",
  other: "Autre moyen de paiement",
};

/** pending → submitted → verified | rejected, or cancelled. See ManualPayment in schema.prisma. */
export const PAYMENT_STATUSES = [
  "pending",
  "submitted",
  "verified",
  "rejected",
  "cancelled",
] as const;
export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

export const STATUS_LABEL: Record<PaymentStatus, string> = {
  pending: "en attente",
  submitted: "en attente de vérification",
  verified: "validé",
  rejected: "refusé",
  cancelled: "annulé",
};

// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g;

/** One line of free text: no control characters, single spaces, trimmed. */
export function cleanLine(value: string): string {
  return value.replace(CONTROL_CHARS, "").replace(/\s+/g, " ").trim();
}

/** Several lines of free text (instructions): line breaks kept, everything else tidied. */
export function cleanMultiline(value: string): string {
  return value
    .replace(/\r\n?/g, "\n")
    .replace(CONTROL_CHARS, "")
    .split("\n")
    .map((line) => line.replace(/[ \t]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * A phone number as typed ("622 12 34 56", "+224 622 123 456", "(224) 622-123-456") checked and
 * reduced to digits with an optional leading "+". Null when it cannot be a phone number.
 */
export function normalizePhone(value: string): string | null {
  const compact = value.replace(/[\s().-]/g, "");
  return /^\+?\d{6,15}$/.test(compact) ? compact : null;
}

/** Merchant codes are short alphanumeric identifiers. */
export function isValidMerchantCode(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9 _-]{1,39}$/.test(value);
}

/** A transaction reference as printed in the operator's confirmation message. */
export function isValidReference(value: string): boolean {
  return /^[A-Za-z0-9._/ -]{4,64}$/.test(value) && referenceKey(value).length >= 4;
}

/**
 * The reference lower-cased and stripped of separators: "TX-12 34" and "tx1234" are the same
 * transaction, so they must count as the same when checking that a reference is used only once.
 */
export function referenceKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, "");
}

/** What may appear in a USSD code once the {placeholders} are set aside. */
const USSD_ALLOWED = /^[0-9*#+]*$/;
const USSD_PLACEHOLDERS = /\{(numero|montant|code)\}/g;

export function isValidUssdTemplate(value: string): boolean {
  return value.length <= 60 && USSD_ALLOWED.test(value.replace(USSD_PLACEHOLDERS, ""));
}

/**
 * The code to dial for "Payer maintenant": the owner's template with {numero}, {montant} and {code}
 * filled in. Null when a placeholder has nothing to fill it (never dial a half-built code) or the
 * result is not a plain USSD string.
 */
export function resolveUssd(
  template: string | null | undefined,
  values: { phone?: string | null; amount: number; code?: string | null },
): string | null {
  if (!template) return null;

  let missing = false;
  const filled = template.replace(USSD_PLACEHOLDERS, (_match, name: string) => {
    const value =
      name === "numero"
        ? (values.phone ?? "").replace(/\D/g, "")
        : name === "montant"
          ? String(Math.round(values.amount))
          : (values.code ?? "").replace(/[^A-Za-z0-9]/g, "");
    if (!value) missing = true;
    return value;
  });

  return missing || !/^[0-9*#+]+$/.test(filled) ? null : filled;
}

/**
 * The steps shown to the customer when the owner wrote none. They depend only on the kind of
 * payment — never on an operator's real menus, which differ by country and change over time.
 */
export function defaultInstructions(provider: PaymentProvider, displayName: string): string[] {
  if (provider === "merchant_code") {
    return [
      `Ouvrez l'application ou le menu de paiement de votre opérateur.`,
      `Choisissez « Paiement marchand » (ou l'option équivalente).`,
      `Saisissez le code marchand indiqué.`,
      `Envoyez exactement le montant affiché.`,
      `Conservez la référence de transaction.`,
      `Revenez dans l'application et cliquez sur « J'ai effectué le paiement ».`,
      `Saisissez votre référence de transaction.`,
      `Votre paiement sera vérifié avant validation.`,
    ];
  }
  const service = provider === "other" ? displayName : PROVIDER_LABEL[provider];
  return [
    `Ouvrez ${service}.`,
    `Effectuez un transfert vers le numéro indiqué.`,
    `Envoyez exactement le montant affiché.`,
    `Conservez la référence de transaction.`,
    `Revenez dans l'application.`,
    `Cliquez sur « J'ai effectué le paiement ».`,
    `Saisissez votre référence de transaction.`,
    `Votre paiement sera vérifié avant validation.`,
  ];
}

/** The custom instructions as steps (one per non-empty line), or the defaults. */
export function instructionSteps(
  provider: PaymentProvider,
  displayName: string,
  custom: string | null | undefined,
): string[] {
  const own = (custom ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  return own.length > 0 ? own : defaultInstructions(provider, displayName);
}
