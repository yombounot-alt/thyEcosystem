/**
 * Port d'envoi de SMS — abstraction fournisseur (docs/blueprint/06-platform-engines.md §2).
 * Le kernel n'appelle jamais un SDK de SMS directement : il dépend de cette interface, implémentée
 * par un adaptateur choisi par configuration (`SMS_DRIVER`). Phase 0 : uniquement l'adaptateur
 * `console` (développement). Les adaptateurs réels (2 fournisseurs + repli WhatsApp/voix, ADR D5)
 * restent à brancher dès qu'un fournisseur est choisi.
 */
export const SMS_SENDER = "SMS_SENDER";

export interface SmsSenderPort {
  sendOtp(phoneE164: string, code: string): Promise<void>;
  /** SMS transactionnel libre (ex. invitation à rejoindre une entreprise). */
  sendText(phoneE164: string, text: string): Promise<void>;
}
