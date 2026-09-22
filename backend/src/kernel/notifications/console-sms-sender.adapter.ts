import { Injectable, Logger } from "@nestjs/common";
import type { SmsSenderPort } from "./sms-sender.port.js";

/** Adaptateur de développement : journalise le code au lieu d'envoyer un vrai SMS. Jamais en production (voir config.ts). */
@Injectable()
export class ConsoleSmsSenderAdapter implements SmsSenderPort {
  private readonly logger = new Logger("sms:console");

  async sendOtp(phoneE164: string, code: string): Promise<void> {
    this.logger.log(`OTP pour ${phoneE164} : ${code}`);
  }
}
