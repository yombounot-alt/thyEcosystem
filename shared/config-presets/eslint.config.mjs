// Preset ESLint partagé (flat config, ESLint 9+). Consommé par backend/ et admin/ via :
//   import thyBase from '@thy/config-presets/eslint';
//   export default [...thyBase, { /* règles spécifiques au paquet */ }];
import js from "@eslint/js";
import importPlugin from "eslint-plugin-import";
import tseslint from "typescript-eslint";
import prettierConfig from "eslint-config-prettier";

export default tseslint.config(
  {
    ignores: ["**/dist/**", "**/build/**", "**/coverage/**", "**/*.gen.ts", "**/*.g.ts"],
  },
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    plugins: { import: importPlugin },
    rules: {
      // Le code métier ne doit jamais avaler une erreur silencieusement (principe §46 du brief).
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "@typescript-eslint/consistent-type-imports": "error",
      "no-console": ["warn", { allow: ["warn", "error"] }],
    },
  },
  prettierConfig,
);
