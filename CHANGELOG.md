# Changelog

Généré par `node tools/changelog.mjs` depuis l'historique Git (Conventional Commits). Ne pas
modifier à la main : le message de commit est la source.

## Non publié — Phase 0 (Foundation)

### Fonctionnalités

- **admin** : staff console with totp sign-in and audited support actions (L0.11) (`cb3c58e`, 2026-10-17)
- **mobile** : thy_core package and app/backend API contract check (L0.10) (`6621d60`, 2026-09-29)
- **mobile** : app shell foundations — flavors, module registry, l10n, design system package (L0.10) (`6b58087`, 2026-09-29)
- **mobile** : team, invitations, notifications and plan screens on the THY design system (L0.9) (`a5a8391`, 2026-09-28)
- **backend** : platform engines, team management and production readiness (L0.8) (`ffd54dd`, 2026-09-28)
- **infra** : add GCP staging terraform, backend dockerfile and infra ci (L0.4) (`512cb0c`, 2026-09-26)
- **mobile** : port the thyBusiness app onto the THY backend (`d93a35d`, 2026-09-23)
- **business** : port thyBusiness onto the kernel (biz schema, RLS, Prisma client) (`30e657a`, 2026-09-23)
- **kernel** : per-member permission overrides, business permissions, storage port (`47e92b8`, 2026-09-23)
- **kernel** : identity, tenancy and RBAC foundation (L0.1-L0.7) (`14c4fd5`, 2026-09-22)

### Corrections

- **ci** : keep turbo off the dart-only tokens build and clear audit findings (`6098160`, 2026-10-17)
- **mobile** : upgrade sentry_flutter to 9.x so Android builds with Kotlin 2.4 (`b5def58`, 2026-09-29)
- **mobile** : enable resValues for Android flavors and annotate CI build failures (`81a3874`, 2026-09-29)
- **ci** : replace MinIO with RustFS and keep turbo off the design tokens (`79e1f40`, 2026-09-28)
- **ci** : correct the trivy-action tag (v0.36.0, not 0.36.0) (`ee87033`, 2026-09-25)
- **backend** : wire ESLint and resolve every finding (`099d292`, 2026-09-25)

### Documentation

- record L0.8 and L0.9 progress in the phase 0 plan (`c2805f9`, 2026-09-28)
- mark Phase 0 kernel/identity/RBAC lots as done (`388341b`, 2026-09-22)
- mark GitHub remote decision as resolved (`7e25a5c`, 2026-09-22)

### CI

- add the CI/CD skeleton (L0.3) (`d0bec36`, 2026-09-25)
