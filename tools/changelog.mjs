// Reconstruit CHANGELOG.md depuis l'historique Git (Conventional Commits, voir commitlint.config.mjs).
//
//   node tools/changelog.mjs
//
// Une version publiée sera marquée par un tag `vX.Y.Z` ; d'ici là, tout est dans « Non publié ».
// Les commits de pure maintenance (chore, style, test) ne sont pas listés.
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const SECTIONS = [
  ["feat", "Fonctionnalités"],
  ["fix", "Corrections"],
  ["perf", "Performances"],
  ["refactor", "Refactorisations"],
  ["docs", "Documentation"],
  ["ci", "CI"],
  ["build", "Build"],
];
const SEP = "\u001f";

const log = execFileSync("git", ["log", `--format=%h${SEP}%ad${SEP}%s`, "--date=short"], {
  encoding: "utf8",
});
const commits = log
  .trim()
  .split("\n")
  .filter(Boolean)
  .map((line) => {
    const [hash, date, subject] = line.split(SEP);
    const m = /^(\w+)(?:\(([^)]+)\))?(!)?: (.+)$/.exec(subject);
    return m
      ? { hash, date, type: m[1], scope: m[2], breaking: Boolean(m[3]), text: m[4] }
      : { hash, date, type: "other", text: subject };
  });

const out = [
  "# Changelog",
  "",
  "Généré par `node tools/changelog.mjs` depuis l'historique Git (Conventional Commits). Ne pas",
  "modifier à la main : le message de commit est la source.",
  "",
  "## Non publié — Phase 0 (Foundation)",
  "",
];
for (const [type, title] of SECTIONS) {
  const items = commits.filter((c) => c.type === type);
  if (!items.length) continue;
  out.push(`### ${title}`, "");
  for (const c of items) {
    const scope = c.scope ? `**${c.scope}** : ` : "";
    const breaking = c.breaking ? " ⚠️ rupture" : "";
    out.push(`- ${scope}${c.text}${breaking} (\`${c.hash}\`, ${c.date})`);
  }
  out.push("");
}
writeFileSync(new URL("../CHANGELOG.md", import.meta.url), `${out.join("\n").trimEnd()}\n`);
process.stdout.write(`CHANGELOG.md : ${String(commits.length)} commits lus.\n`);
