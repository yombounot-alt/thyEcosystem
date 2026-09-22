import { HttpException } from "@nestjs/common";

/** Erreur applicative : `code` stable et machine-lisible, `message` en français pour l'utilisateur. */
export class AppError extends HttpException {
  constructor(
    readonly code: string,
    status: number,
    message: string,
    readonly details?: unknown,
  ) {
    super({ code, message, details }, status);
  }
}

export const badRequest = (code: string, message: string, details?: unknown) =>
  new AppError(code, 400, message, details);
export const unauthorized = (code = "AUTH_UNAUTHENTICATED", message = "Authentification requise") =>
  new AppError(code, 401, message);
export const forbidden = (code: string, message: string, details?: unknown) =>
  new AppError(code, 403, message, details);
export const notFound = (message = "Ressource introuvable") =>
  new AppError("NOT_FOUND", 404, message);
export const conflict = (code: string, message: string, details?: unknown) =>
  new AppError(code, 409, message, details);
export const unprocessable = (code: string, message: string, details?: unknown) =>
  new AppError(code, 422, message, details);
export const tooMany = (code: string, message: string, retryAfterSec?: number) =>
  new AppError(code, 429, message, retryAfterSec ? { retryAfterSec } : undefined);
