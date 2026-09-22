import { Inject, Injectable, type LoggerService } from "@nestjs/common";
import { pino, type Logger } from "pino";
import { CONFIG, type AppConfig } from "./config/config.js";

// Masquage systématique des champs sensibles dans les journaux (docs/blueprint/11-security.md §7).
const REDACT = [
  "req.headers.authorization",
  "headers.authorization",
  "*.password",
  "*.newPassword",
  "*.token",
  "*.refreshToken",
  "*.accessToken",
  "*.code",
  "*.phone",
  "*.pushToken",
];

@Injectable()
export class AppLogger implements LoggerService {
  readonly pino: Logger;

  constructor(@Inject(CONFIG) cfg: AppConfig) {
    this.pino = pino({
      level: cfg.env === "test" ? "silent" : cfg.env === "production" ? "info" : "debug",
      redact: { paths: REDACT, censor: "[REDACTED]" },
      base: { service: "thy-backend" },
    });
  }

  log(message: unknown, ...rest: unknown[]) {
    this.pino.info({ ctx: rest.at(-1) }, String(message));
  }
  error(message: unknown, ...rest: unknown[]) {
    this.pino.error(
      { ctx: rest.at(-1), trace: rest.length > 1 ? String(rest[0]) : undefined },
      String(message),
    );
  }
  warn(message: unknown, ...rest: unknown[]) {
    this.pino.warn({ ctx: rest.at(-1) }, String(message));
  }
  debug(message: unknown, ...rest: unknown[]) {
    this.pino.debug({ ctx: rest.at(-1) }, String(message));
  }
  verbose(message: unknown, ...rest: unknown[]) {
    this.pino.trace({ ctx: rest.at(-1) }, String(message));
  }
}
