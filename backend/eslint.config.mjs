// Lint du backend : préréglage partagé (shared/config-presets/eslint.config.mjs), complété par le
// pointeur vers le tsconfig du paquet (requis pour les règles typées `strictTypeChecked`).
import thyBase from "@thy/config-presets/eslint";

export default [
  ...thyBase,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    // Le migrateur et le point d'entrée journalisent volontairement en console (pas de logger
    // structuré disponible avant que Nest ait démarré).
    files: ["src/main.ts", "src/database/migrate-cli.ts"],
    rules: { "no-console": "off" },
  },
  {
    // Tests (unitaires et e2e) : `supertest`/`fetch` renvoient des corps de réponse non typés
    // (`any`) par nature — les règles « unsafe » n'apportent ici aucun signal (elles ne
    // détecteraient jamais qu'un vrai bug de typage métier, seulement le shape de `res.body`).
    // Le reste du préréglage (promesses non gérées, imports, variables inutilisées…) reste actif :
    // ce sont ces règles-là qui repèrent de vraies erreurs dans les tests.
    files: ["test/**/*.ts", "src/**/*.spec.ts"],
    rules: {
      "@typescript-eslint/no-unsafe-argument": "off",
      "@typescript-eslint/no-unsafe-assignment": "off",
      "@typescript-eslint/no-unsafe-call": "off",
      "@typescript-eslint/no-unsafe-member-access": "off",
      "@typescript-eslint/no-unsafe-return": "off",
      "@typescript-eslint/restrict-template-expressions": "off",
      "@typescript-eslint/no-non-null-assertion": "off",
      "@typescript-eslint/no-explicit-any": "off",
    },
  },
];
