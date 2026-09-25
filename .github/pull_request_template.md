<!--
Merci ! Remplis ce que tu peux — une PR petite et ciblée (Conventional Commits, voir
commitlint.config.mjs) est plus facile à relire qu'une PR qui coche toutes les cases.
-->

## Quoi, et pourquoi

<!-- Une ou deux phrases. Lien vers le lot du plan (docs/plans/phase-0-foundation.md) si applicable. -->

## Checklist (toute PR)

Principes absolus du projet (voir docs/blueprint/README.md §7 et memory) :

- [ ] Le serveur reste la seule source de vérité (aucune logique de confiance côté client).
- [ ] Aucun paiement simulé ; aucune donnée fictive activable en production.
- [ ] Isolation multi-tenant (RLS) respectée pour toute nouvelle table/requête.
- [ ] Aucun secret, jeton ou donnée personnelle dans le code, les logs ou cette PR.
- [ ] Tests ajoutés/mis à jour pour ce changement (`pnpm test`, `pnpm test:e2e` en local ou CI).
- [ ] `pnpm lint`, `pnpm typecheck`, `pnpm format:check` passent (ou la CI le confirmera).
- [ ] Documentation (blueprint/plans/ADR) mise à jour si ce changement touche une décision qui y est décrite.

## Si cette PR termine un module

Coche la [Definition of Done complète](../docs/blueprint/10-testing.md#8-definition-of-done--module) (threat model, i18n, goldens, dashboards, feature flag…) avant de le marquer « fait » dans le plan — sinon ignore cette section.
