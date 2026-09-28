import { Injectable, Logger } from "@nestjs/common";
import type { PushMessage, PushResult, PushSenderPort } from "./push-sender.port.js";

/**
 * Adaptateur de développement : journalise l'envoi au lieu de contacter FCM. Ne journalise ni les
 * jetons ni le contenu (qui peut nommer une personne) — seulement le nombre d'appareils visés.
 * Jamais en production (voir config.ts).
 */
@Injectable()
export class ConsolePushSenderAdapter implements PushSenderPort {
  private readonly logger = new Logger("push:console");

  send(tokens: string[], message: PushMessage): Promise<PushResult> {
    this.logger.log(`push « ${message.data.type ?? "?"} » vers ${tokens.length} appareil(s)`);
    return Promise.resolve({ invalidTokens: [] });
  }
}
