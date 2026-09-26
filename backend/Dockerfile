# Image du backend THY (service Cloud Run "api" et job "migrate" — même image, entrypoint
# différent). Contexte de build : LA RACINE du dépôt (nécessaire pour un espace de travail pnpm) —
# voir infra/terraform/environments/staging/README.md ou la CI de déploiement pour la commande
# `docker build` exacte.
#
# node:22-bookworm-slim (glibc, pas Alpine/musl) : @node-rs/argon2 est un module natif dont les
# binaires prégénérés visent glibc en priorité — Alpine économiserait quelques Mo au prix d'un
# risque de compatibilité qui n'en vaut pas la peine ici. openssl est requis par le moteur Prisma,
# aussi bien pour `prisma generate` (à la compilation) que pour se connecter à Postgres (à
# l'exécution) — l'image slim ne l'inclut pas par défaut.

FROM node:22-bookworm-slim AS base
WORKDIR /app
# npm install plutôt que `corepack enable` : corepack télécharge pnpm à la première invocation,
# une dépendance réseau supplémentaire à chaque build qui s'est révélée peu fiable ici.
RUN npm install --global pnpm@10.15.0 \
  && apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# ─── deps : dépendances complètes (dev incluses) pour compiler ───────────────────────────────────
FROM base AS deps
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY backend/package.json backend/package.json
COPY shared/config-presets/package.json shared/config-presets/package.json
# --ignore-scripts : `backend`'s postinstall (`prisma generate`) a besoin de prisma/schema.prisma,
# qui n'existe pas encore à ce stade (seuls les package.json sont copiés, pour que ce layer reste en
# cache tant que les dépendances ne changent pas) — le stage `build` l'exécute lui-même une fois le
# code source en place, via son propre script `build` (prisma generate && nest build).
RUN pnpm install --frozen-lockfile --ignore-scripts

# ─── build : compile TypeScript → JavaScript ─────────────────────────────────────────────────────
FROM deps AS build
COPY shared/config-presets shared/config-presets
COPY backend backend
RUN pnpm --filter @thy/backend run build

# ─── runtime : image finale, non-root ────────────────────────────────────────────────────────────
# node_modules vient tel quel du stage `build` (dev comprises : typescript, vitest, eslint…) plutôt
# que d'un install `--prod` séparé : pnpm place le client Prisma généré dans son magasin content-
# addressable racine (node_modules/.pnpm/…), pas dans un dossier `.prisma` isolable proprement à la
# COPY. Élaguer les devDependencies (ex. via `pnpm deploy`) est une optimisation de taille d'image à
# faire plus tard, pas un prérequis pour que ça marche.
FROM node:22-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --gid 1001 thy \
  && useradd --uid 1001 --gid thy --shell /bin/false --no-create-home thy

COPY --from=build --chown=thy:thy /app/node_modules ./node_modules
COPY --from=build --chown=thy:thy /app/backend/node_modules ./backend/node_modules
COPY --from=build --chown=thy:thy /app/backend/dist ./backend/dist
COPY --from=build --chown=thy:thy /app/backend/package.json ./backend/package.json
COPY --from=build --chown=thy:thy /app/backend/migrations ./backend/migrations

WORKDIR /app/backend
USER thy

# Cloud Run fixe PORT (8080 par défaut) et l'injecte tout seul ; ne pas le redéfinir ici.
EXPOSE 8080
CMD ["node", "dist/main.js"]
