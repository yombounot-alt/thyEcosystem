import { ValidationPipe, type INestApplication } from "@nestjs/common";
import { json, type NextFunction, type Request, type Response } from "express";
import helmet from "helmet";
import { randomUUID } from "node:crypto";
import type { AppConfig } from "./kernel/config/config.js";

/**
 * Configuration HTTP commune à la production et aux tests (les tests exercent donc EXACTEMENT
 * la même chaîne : en-têtes, validation stricte, limites). Référence : docs/blueprint/11-security.md §3.7.
 */
export function configureApp(app: INestApplication, cfg: AppConfig): void {
  const http = app.getHttpAdapter().getInstance() as {
    set: (k: string, v: unknown) => void;
    disable: (k: string) => void;
  };
  http.set("trust proxy", cfg.trustProxy);
  http.disable("x-powered-by");

  app.use((req: Request & { id?: string }, res: Response, next: NextFunction) => {
    req.id = randomUUID();
    res.setHeader("x-request-id", req.id);
    next();
  });
  app.use(
    helmet({
      contentSecurityPolicy: { directives: { defaultSrc: ["'none'"], frameAncestors: ["'none'"] } },
      crossOriginResourcePolicy: { policy: "same-site" },
    }),
  );
  app.use(json({ limit: "100kb" }));
  if (cfg.corsOrigins.length) app.enableCors({ origin: cfg.corsOrigins, credentials: false });

  // Whitelist stricte : toute propriété inconnue ⇒ 400 (empêche le mass-assignment de status, tokenVersion…).
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      validationError: { target: false, value: false },
    }),
  );
  app.setGlobalPrefix("api/v1", { exclude: ["health/live", "health/ready"] });
  app.enableShutdownHooks();
}
