/**
 * Port d'envoi de notifications push (FCM) — abstraction fournisseur, comme SmsSenderPort
 * (docs/blueprint/06-platform-engines.md §2). Phase 0 : seul l'adaptateur `console` existe (aucun
 * projet Firebase réel) ; la configuration de production le REFUSE (voir config.ts).
 */
export const PUSH_SENDER = "PUSH_SENDER";

export interface PushMessage {
  title: string;
  body: string;
  /** Données applicatives (routage dans l'app) — jamais de donnée personnelle sensible. */
  data: Record<string, string>;
}

export interface PushResult {
  /** Jetons que le fournisseur déclare définitivement invalides (app désinstallée…) : à révoquer. */
  invalidTokens: string[];
}

export interface PushSenderPort {
  send(tokens: string[], message: PushMessage): Promise<PushResult>;
}
