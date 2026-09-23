import swc from "unplugin-swc";
import { defineConfig } from "vitest/config";

// Tests unitaires (rapides, sans base de données) : `src/**/*.spec.ts`.
// SWC est nécessaire : esbuild (vitest par défaut) ne sait pas émettre `emitDecoratorMetadata`,
// dont l'injection de dépendances NestJS dépend.
export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: ["src/**/*.spec.ts"],
  },
  plugins: [swc.vite({ module: { type: "es6" } })],
});
