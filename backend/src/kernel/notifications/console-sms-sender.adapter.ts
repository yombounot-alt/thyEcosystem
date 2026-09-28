import { Injectable, Logger } from "@nestjs/common";
import type { SmsSenderPort } from "./sms-sender.port.js";

/** `+224620001234` → `+224•••••34` : assez pour s'y retrouver en développement, sans journaliser un numéro. */
export function maskPhone(phoneE164: string): string {
  if (phoneE164.length <= 6) return "•••";
  return `${phoneE164.slice(0, 4)}${"•".repeat(Math.max(3, phoneE164.length - 6))}${phoneE164.slice(-2)}`;
}

/**
 * Adaptateur de développement : journalise le code au lieu d'envoyer un vrai SMS (c'est sa raison
 * d'être : sans lui, personne ne pourrait se connecter en local). Le numéro, lui, est masqué — le
 * code seul, détaché de son numéro, ne permet pas de se connecter à un compte.
 * Jamais en production (voir config.ts).
 */
@Injectable()
export class ConsoleSmsSenderAdapter implements SmsSenderPort {
  private readonly logger = new Logger("sms:console");

  // Pas de `async` : rien ici n'attend quoi que ce soit (voir SmsSenderPort — un adaptateur qui
  // enverrait un vrai SMS, lui, aurait un corps async).
  sendOtp(phoneE164: string, code: string): Promise<void> {
    this.logger.log(`OTP pour ${maskPhone(phoneE164)} : ${code}`);
    return Promise.resolve();
  }

  sendText(phoneE164: string, text: string): Promise<void> {
    this.logger.log(`SMS pour ${maskPhone(phoneE164)} (${text.length} caractères)`);
    return Promise.resolve();
  }
}
