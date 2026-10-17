/// <reference types="vitest/config" />
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// En développement, l'API admin est servie par le backend sous /admin/v1 : le proxy garde tout sur
// la même origine, ce qu'exige le cookie de session (SameSite=Strict, chemin /admin/v1).
const apiTarget = process.env.THY_API_URL ?? "http://localhost:3300";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5174,
    strictPort: true,
    proxy: { "/admin/v1": { target: apiTarget, changeOrigin: false } },
  },
  build: { sourcemap: true },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    css: false,
  },
});
