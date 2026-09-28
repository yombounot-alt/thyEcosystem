import { HttpException, NotFoundException, type ArgumentsHost } from "@nestjs/common";
import { isHealthProbe, redisStatement } from "../../instrumentation.js";
import { unprocessable } from "../errors.js";
import { AllExceptionsFilter } from "../filters/all-exceptions.filter.js";
import type { AppLogger } from "../logger.js";
import type { ErrorContext, ErrorReporterPort } from "./error-reporter.port.js";
import { scrubEvent, type ScrubbableEvent } from "./scrub.js";

describe("scrubEvent — rien de personnel ne part vers Sentry", () => {
  it("ne garde que la méthode HTTP et l'identifiant technique de l'utilisateur", () => {
    const event = {
      message: "boom",
      request: {
        method: "POST",
        url: "https://api.thy.test/api/v1/auth/otp/verify?phone=+224620000000",
        headers: { authorization: "Bearer secret" },
        data: { phone: "+224620000000", code: "123456" },
        cookies: { session: "x" },
        query_string: "phone=+224620000000",
      },
      user: { id: "u-1", ip_address: "41.1.2.3", phone: "+224620000000" },
      breadcrumbs: [{ message: "GET /me?phone=…" }],
      extra: { body: { phone: "+224620000000" } },
      server_name: "api-7f9",
    };
    const clean = scrubEvent(event);
    expect(clean).toEqual({ message: "boom", request: { method: "POST" }, user: { id: "u-1" } });
    expect(JSON.stringify(clean)).not.toMatch(/224620000000|secret|123456|41\.1\.2\.3/);
  });

  it("laisse passer un événement sans requête ni utilisateur", () => {
    const event: ScrubbableEvent & { message: string } = { message: "outbox" };
    expect(scrubEvent(event)).toEqual({ message: "outbox" });
  });
});

describe("AllExceptionsFilter — ne remonte que les erreurs serveur", () => {
  const captured: { error: unknown; ctx?: ErrorContext }[] = [];
  const reporter: ErrorReporterPort = {
    capture: (error, ctx) => captured.push({ error, ctx }),
    flush: () => Promise.resolve(),
  };
  const logger = { error: () => undefined } as unknown as AppLogger;
  const filter = new AllExceptionsFilter(logger, reporter);

  function run(exception: unknown) {
    let status = 0;
    let body: unknown;
    const res = {
      status(s: number) {
        status = s;
        return this;
      },
      json(b: unknown) {
        body = b;
      },
    };
    const req = {
      id: "req-42",
      method: "POST",
      route: { path: "/products/:id" },
      user: { id: "user-7" },
      membership: { businessId: "biz-3" },
    };
    const host = {
      switchToHttp: () => ({ getResponse: () => res, getRequest: () => req }),
    } as unknown as ArgumentsHost;
    filter.catch(exception, host);
    return { status, body };
  }

  beforeEach(() => {
    captured.length = 0;
  });

  it("une exception inattendue (500) est remontée avec son contexte technique", () => {
    const boom = new Error("connexion perdue");
    const { status, body } = run(boom);
    expect(status).toBe(500);
    expect(body).toEqual({
      error: {
        code: "INTERNAL_ERROR",
        message: "Une erreur interne est survenue",
        requestId: "req-42",
      },
    });
    expect(captured).toEqual([
      {
        error: boom,
        ctx: {
          requestId: "req-42",
          method: "POST",
          route: "/products/:id",
          userId: "user-7",
          businessId: "biz-3",
        },
      },
    ]);
  });

  it("les réponses normales de l'API (4xx) ne sont pas des incidents", () => {
    run(new NotFoundException());
    run(unprocessable("OTP_INVALID", "Code invalide"));
    run(new HttpException("Trop de requêtes", 429));
    expect(captured).toEqual([]);
  });
});

describe("instrumentation OpenTelemetry — confidentialité", () => {
  it("n'envoie de Redis que le nom de la commande", () => {
    expect(redisStatement("incr")).toBe("INCR");
  });

  it("ignore les sondes de santé", () => {
    expect(isHealthProbe("/health/ready")).toBe(true);
    expect(isHealthProbe("/api/v1/products")).toBe(false);
    expect(isHealthProbe(undefined)).toBe(false);
  });
});
