// Lint de l'admin : préréglage partagé + règles des hooks React.
import thyBase from "@thy/config-presets/eslint";
import reactHooks from "eslint-plugin-react-hooks";

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
    files: ["**/*.tsx", "**/*.ts"],
    plugins: { "react-hooks": reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      // Les gestionnaires d'événements React peuvent être async (formulaires).
      "@typescript-eslint/no-misused-promises": [
        "error",
        { checksVoidReturn: { attributes: false } },
      ],
    },
  },
  {
    files: ["src/**/*.test.tsx", "src/test/**"],
    rules: {
      "@typescript-eslint/no-non-null-assertion": "off",
      "@typescript-eslint/no-unsafe-assignment": "off",
      "@typescript-eslint/no-unsafe-member-access": "off",
    },
  },
  { ignores: ["eslint.config.mjs"] },
];
