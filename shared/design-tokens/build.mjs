#!/usr/bin/env node
// Générateur des tokens de design THY : tokens.json (source unique) → Dart (app Flutter) + CSS (admin).
// Sans dépendance (choix assumé plutôt que Style Dictionary : un seul format source, deux sorties
// simples, et le contrôle de contraste WCAG au même endroit).
//
//   node build.mjs          écrit les fichiers générés
//   node build.mjs --check  échoue si un fichier généré n'est pas à jour ou si un contraste casse
//
// Référence : docs/brand/README.md §3–6.
import { readFileSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const tokens = JSON.parse(readFileSync(join(here, "tokens.json"), "utf8"));

const DS_PACKAGE = join(root, "mobile", "packages", "thy_design_system");
const OUT_DART = join(DS_PACKAGE, "lib", "src", "theme", "thy_tokens.g.dart");
const OUT_CSS = join(here, "build", "tokens.css");
const MIN = { text: 4.5, ui: 3 };

const HEX = /^#[0-9A-F]{6}$/;
const clean = (obj) => Object.entries(obj).filter(([k]) => !k.startsWith("$"));

// ─── Validation ───────────────────────────────────────────────────────────────────────────────
const errors = [];
for (const [family, scale] of clean(tokens.primitives))
  for (const [step, hex] of clean(scale))
    if (!HEX.test(hex)) errors.push(`primitives.${family}.${step} : « ${hex} » n'est pas #RRGGBB`);

const light = Object.fromEntries(clean(tokens.semantic.light));
const dark = Object.fromEntries(clean(tokens.semantic.dark));
const names = Object.keys(light);
for (const [mode, set] of [
  ["light", light],
  ["dark", dark],
]) {
  for (const [name, hex] of Object.entries(set))
    if (!HEX.test(hex)) errors.push(`semantic.${mode}.${name} : « ${hex} » n'est pas #RRGGBB`);
}
const missing = names
  .filter((n) => !(n in dark))
  .concat(Object.keys(dark).filter((n) => !(n in light)));
if (missing.length) errors.push(`tokens présents dans un seul mode : ${missing.join(", ")}`);

// ─── Contraste WCAG 2.x ───────────────────────────────────────────────────────────────────────
function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
export function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}
const report = [];
for (const kind of ["text", "ui"])
  for (const [fg, bg] of tokens.contrast[kind])
    for (const [mode, set] of [
      ["clair", light],
      ["sombre", dark],
    ]) {
      if (!set[fg] || !set[bg]) {
        errors.push(`contraste : token inconnu ${fg} / ${bg}`);
        continue;
      }
      const ratio = contrast(set[fg], set[bg]);
      report.push(`${ratio.toFixed(2).padStart(6)}:1  ${mode.padEnd(6)} ${kind} ${fg} sur ${bg}`);
      if (ratio < MIN[kind])
        errors.push(
          `contraste insuffisant (${mode}) : ${fg} ${set[fg]} sur ${bg} ${set[bg]} = ${ratio.toFixed(2)}:1 < ${MIN[kind]}:1`,
        );
    }

// ─── Génération ───────────────────────────────────────────────────────────────────────────────
const header = (c) =>
  `${c} GÉNÉRÉ par shared/design-tokens/build.mjs depuis tokens.json — NE PAS MODIFIER À LA MAIN.\n`;
const argb = (hex) => `Color(0xFF${hex.slice(1)})`;
const pascal = (s) => s.charAt(0).toUpperCase() + s.slice(1);

function dart() {
  const prim = clean(tokens.primitives)
    .flatMap(([family, scale]) =>
      clean(scale).map(([step, hex]) => `  static const ${family}${pascal(step)} = ${argb(hex)};`),
    )
    .join("\n");
  const fields = names.map((n) => `  final Color ${n};`).join("\n");
  const ctorParams = names.map((n) => `    required this.${n},`).join("\n");
  const values = (set) => names.map((n) => `    ${n}: ${argb(set[n])},`).join("\n");
  const copyParams = names.map((n) => `Color? ${n}`).join(", ");
  const copyBody = names.map((n) => `      ${n}: ${n} ?? this.${n},`).join("\n");
  const lerpBody = names.map((n) => `      ${n}: Color.lerp(${n}, other.${n}, t)!,`).join("\n");
  return `${header("//")}// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

/// Primitives de la marque THY (docs/brand/README.md §3). Préférer les couleurs sémantiques
/// ([ThyColors]) dans les écrans : seules elles s'adaptent au mode sombre.
abstract final class ThyPalette {
${prim}
}

/// Couleurs sémantiques THY (docs/brand/README.md §4), une valeur par mode. Accès :
/// \`context.colors.primary\` (voir app_theme.dart).
@immutable
class ThyColors extends ThemeExtension<ThyColors> {
  const ThyColors({
${ctorParams}
  });

${fields}

  static const light = ThyColors(
${values(light)}
  );

  static const dark = ThyColors(
${values(dark)}
  );

  @override
  ThyColors copyWith({${copyParams}}) {
    return ThyColors(
${copyBody}
    );
  }

  @override
  ThyColors lerp(ThemeExtension<ThyColors>? other, double t) {
    if (other is! ThyColors) return this;
    return ThyColors(
${lerpBody}
    );
  }
}
`;
}

function css() {
  const kebab = (s) => s.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`);
  const prim = clean(tokens.primitives)
    .flatMap(([family, scale]) =>
      clean(scale).map(([step, hex]) => `  --thy-${family}-${step}: ${hex};`),
    )
    .join("\n");
  const sem = (set) => names.map((n) => `  --thy-${kebab(n)}: ${set[n]};`).join("\n");
  const semIndented = (set) => names.map((n) => `    --thy-${kebab(n)}: ${set[n]};`).join("\n");
  return `${header("/*").replace("\n", " */\n")}
:root {
${prim}
${sem(light)}
  color-scheme: light;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
${semIndented(dark)}
    color-scheme: dark;
  }
}

:root[data-theme="dark"] {
${sem(dark)}
  color-scheme: dark;
}
`;
}

/**
 * Le Dart généré passe par `dart format` (le même que la CI mobile exige) : sans ça, le formateur
 * réécrirait le fichier et le contrôle « à jour » échouerait. Nécessite `dart` dans le PATH
 * (fourni par Flutter).
 */
function dartFormat(source) {
  // Formaté DANS le paquet design system : `dart format` y applique sa largeur de ligne
  // (analysis_options.yaml), exactement comme la CI.
  const dir = join(DS_PACKAGE, ".dart_tool");
  mkdirSync(dir, { recursive: true });
  const file = join(dir, `thy_tokens.${process.pid}.tmp.dart`);
  try {
    writeFileSync(file, source);
    const res = spawnSync(`dart format "${file}"`, { shell: true, encoding: "utf8" });
    if (res.status !== 0)
      throw new Error(`dart format a échoué (dart est-il dans le PATH ?) : ${res.stderr}`);
    return readFileSync(file, "utf8");
  } finally {
    rmSync(file, { force: true });
  }
}

const outputs = [
  [OUT_DART, dartFormat(dart())],
  [OUT_CSS, css()],
];

const check = process.argv.includes("--check");
if (check) {
  for (const [file, content] of outputs) {
    let current = "";
    try {
      current = readFileSync(file, "utf8");
    } catch {
      /* absent */
    }
    if (current.replace(/\r\n/g, "\n") !== content)
      errors.push(`${file} n'est pas à jour : lancer \`node shared/design-tokens/build.mjs\``);
  }
}

if (process.argv.includes("--report")) console.log(report.join("\n"));
if (errors.length) {
  console.error(`Tokens de design invalides :\n - ${errors.join("\n - ")}`);
  process.exit(1);
}
if (!check) {
  for (const [file, content] of outputs) {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, content);
  }
  console.log(
    `Tokens générés (${names.length} sémantiques × 2 modes) :\n - ${outputs.map(([f]) => f).join("\n - ")}`,
  );
} else {
  console.log(`Tokens à jour ; ${report.length} contrastes vérifiés.`);
}
