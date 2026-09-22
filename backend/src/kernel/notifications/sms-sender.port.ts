/**
 * Port d'envoi de SMS — abstraction fournisseur (docs/blueprint/06-platform-engines.md §2).
 * Le kernel n'appelle jamais un SDK de SMS directement : il dépend de cette interface, implémentée
 * par un adaptateur choisi par configuration (`SMS_DRIVER`). Phase 0 : uniquement l'adaptateur
 * `console` (développement). Les adaptateurs réels (2 fournisseurs + repli WhatsApp/voix, ADR D5)
 * sont un travail de Phase 1, pas du kernel.
 */
export const SMS_SENDER = "SMS_SENDER";

export interface SmsSenderPort {
  sendOtp(phoneE164: string, code: string): Promise<void>;
}
