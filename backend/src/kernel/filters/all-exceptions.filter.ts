import { ArgumentsHost, Catch, ExceptionFilter, HttpException } from "@nestjs/common";
import type { Response } from "express";
import type { AuthedRequest } from "../auth/auth-types.js";
import { AppError } from "../errors.js";
import { AppLogger } from "../logger.js";

interface PgError {
  code?: string;
  constraint?: string;
  message: string;
}
function isPgError(e: unknown): e is PgError {
  if (typeof e !== "object" || e === null) return false;
  const err = e as PgError;
  return typeof err.code === "string" && /^[0-9A-Z]{5}$/.test(err.code);
}

interface PrismaKnownError {
  name: string;
  code: string;
  message: string;
}
const isPrismaKnownError = (e: unknown): e is PrismaKnownError =>
  typeof e === "object" &&
  e !== null &&
  (e as PrismaKnownError).name === "PrismaClientKnownRequestError" &&
  typeof (e as PrismaKnownError).code === "string";

const HTTP_CODES: Record<number, string> = {
  400: "BAD_REQUEST",
  401: "AUTH_UNAUTHENTICATED",
  403: "FORBIDDEN",
  404: "NOT_FOUND",
  413: "PAYLOAD_TOO_LARGE",
  429: "RATE_LIMITED",
};

/**
 * Format d'erreur unique, conforme RFC 9457 simplifié : { error: { code, message, details?, requestId } }.
 * Aucune stack, aucun détail SQL, aucun message interne n'est jamais renvoyé au client.
 * Référence : docs/blueprint/05-api.md §3.1.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  constructor(private readonly logger: AppLogger) {}

  catch(exception: unknown, host: ArgumentsHost): void {
    const http = host.switchToHttp();
    const res = http.getResponse<Response>();
    const req = http.getRequest<AuthedRequest>();

    let status = 500;
    let code = "INTERNAL_ERROR";
    let message = "Une erreur interne est survenue";
    let details: unknown;

    if (exception instanceof AppError) {
      status = exception.getStatus();
      code = exception.code;
      message = exception.message;
      details = exception.details;
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse() as { message?: unknown };
      if (status === 400 && Array.isArray(body.message)) {
        code = "VALIDATION_FAILED";
        message = "Données invalides";
        details = body.message;
      } else {
        code = HTTP_CODES[status] ?? "HTTP_ERROR";
        message =
          status === 404
            ? "Ressource introuvable"
            : status === 413
              ? "Contenu trop volumineux"
              : exception.message;
      }
    } else if (isPrismaKnownError(exception)) {
      // Erreurs Prisma non déjà converties par le service métier (le kernel ne dépend pas de Prisma :
      // détection par nom/code). P2023 = identifiant mal formé (UUID) ⇒ ressource introuvable.
      ({ status, code, message } = this.mapPrisma(exception));
      if (status === 500)
        this.logger.error(`prisma ${exception.code}: ${exception.message}`, undefined, "db");
    } else if (isPgError(exception)) {
      ({ status, code, message } = this.mapPg(exception));
      if (status === 500)
        this.logger.error(`pg ${exception.code}: ${exception.message}`, undefined, "db");
    } else {
      this.logger.error(
        exception instanceof Error ? exception.message : String(exception),
        exception instanceof Error ? exception.stack : undefined,
        "unhandled",
      );
    }

    res.status(status).json({
      error: { code, message, ...(details !== undefined ? { details } : {}), requestId: req.id },
    });
  }

  private mapPrisma(e: PrismaKnownError): { status: number; code: string; message: string } {
    switch (e.code) {
      case "P2002":
        return { status: 409, code: "CONFLICT", message: "Cette ressource existe déjà" };
      case "P2003":
        return {
          status: 409,
          code: "CONFLICT",
          message: "Cette ressource est référencée ailleurs",
        };
      case "P2023":
      case "P2025":
        return { status: 404, code: "NOT_FOUND", message: "Ressource introuvable" };
      default:
        return { status: 500, code: "INTERNAL_ERROR", message: "Une erreur interne est survenue" };
    }
  }

  private mapPg(e: PgError): { status: number; code: string; message: string } {
    switch (e.code) {
      case "23505":
        return { status: 409, code: "CONFLICT", message: "Cette ressource existe déjà" };
      case "23514":
        return { status: 422, code: "CONSTRAINT_VIOLATION", message: "Données incohérentes" };
      case "23503":
        return { status: 422, code: "INVALID_REFERENCE", message: "Référence invalide" };
      case "22P02": // texte invalide (ex. UUID mal formé)
        return { status: 404, code: "NOT_FOUND", message: "Ressource introuvable" };
      default:
        return { status: 500, code: "INTERNAL_ERROR", message: "Une erreur interne est survenue" };
    }
  }
}
