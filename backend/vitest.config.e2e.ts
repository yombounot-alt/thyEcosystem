import swc from "unplugin-swc";
import { defineConfig } from "vitest/config";

// Tests e2e : application NestJS complète + PostgreSQL/Redis de développement (docker compose).
// Les fichiers partagent une base ; on les exécute donc l'un après l'autre.
export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: ["test/**/*.e2e-spec.ts"],
    testTimeout: 30_000,
    hookTimeout: 60_000,
    fileParallelism: false,
    setupFiles: ["test/setup-env.ts"],
  },
  plugins: [swc.vite({ module: { type: "es6" } })],
});
