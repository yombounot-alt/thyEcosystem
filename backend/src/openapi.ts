import type { INestApplication } from "@nestjs/common";
import { DocumentBuilder, SwaggerModule, type OpenAPIObject } from "@nestjs/swagger";

export const OPENAPI_PATH = "/api/v1/openapi.json";

/**
 * Contrat OpenAPI de l'API, construit depuis les contrôleurs et les DTO (le plugin Swagger du
 * compilateur Nest — nest-cli.json — déduit les schémas des règles class-validator).
 * Référence : docs/blueprint/05-api.md. Le client mobile pourra en être généré (L0.10).
 */
export function buildOpenApiDocument(app: INestApplication): OpenAPIObject {
  const config = new DocumentBuilder()
    .setTitle("THY API")
    .setDescription(
      "API de l'écosystème THY. Authentification : jeton d'accès (Bearer) obtenu par OTP " +
        "(POST /auth/otp/request puis /auth/otp/verify). Erreurs : { error: { code, message, " +
        "details?, requestId } }. Les routes « à plat » de THY Business (ex. /products) visent " +
        "l'entreprise active du jeton (POST /businesses/{id}/activate).",
    )
    .setVersion("1")
    .addServer("/api/v1")
    .addBearerAuth({ type: "http", scheme: "bearer", bearerFormat: "JWT" })
    .build();
  // Les chemins sont documentés relativement au serveur `/api/v1` (préfixe global retiré).
  return SwaggerModule.createDocument(app, config, { ignoreGlobalPrefix: true });
}

/**
 * Sert le contrat en JSON (pas d'interface Swagger UI : la CSP de l'API — `default-src 'none'` —
 * bloquerait ses scripts, et on ne l'affaiblit pas). Désactivé par défaut en production
 * (OPENAPI_ENABLED) : la surface de l'API n'a pas à être publiée.
 */
export function mountOpenApi(app: INestApplication): void {
  let document: OpenAPIObject | undefined;
  const http = app.getHttpAdapter();
  http.get(OPENAPI_PATH, (_req: unknown, res: { json(body: unknown): void }) => {
    document ??= buildOpenApiDocument(app);
    res.json(document);
  });
}
