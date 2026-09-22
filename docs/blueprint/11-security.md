# 11 — Stratégie de sécurité

Couvre le point 21. Référentiels visés : **OWASP ASVS niveau 2** (backend/admin), **OWASP MASVS** (mobile), **OWASP API Security Top 10** (BOLA/IDOR en tête), **OWASP Top 10**.

---

## 1. Principes
1. **Le serveur est la seule autorité** : identifiants, prix, totaux, statuts de paiement, éligibilité, rôles sont recalculés/vérifiés côté serveur.
2. **Défense en profondeur** : chaque contrôle critique existe à **plusieurs couches** (garde API + politique métier + RLS).
3. **Fail closed** : absence de contexte ⇒ refus / zéro ligne.
4. **Moindre privilège** : rôles DB, rôles staff, permissions Business, portées des API keys, outils IA.
5. **Rien de sensible dans les logs, le dépôt ou l'app mobile.**
6. **Tout ce qui compte est traçable** (audit append-only).

## 2. Modèle de menaces — points d'attention par module

| Module / composant | Menaces principales | Contre-mesures clés |
|---|---|---|
| **Auth** | SMS pumping, brute force OTP, énumération, SIM swap, vol de session | Limites multi-clés, attestation d'appareil, plafonds de coût, délais de récupération, rotation + détection de réutilisation |
| **Business** | Fuite inter-tenant, fraude interne (remboursements, remises), falsification d'historique | RLS + FK composites, permissions fines + seuils, journaux append-only, audit |
| **Marketplace** | Faux vendeurs, manipulation de prix côté client, faux avis, contournement de paiement | Recalcul serveur, éligibilité d'avis, vérification, messagerie surveillée |
| **Paiements** | Webhook forgé/rejoué, altération de montant, double crédit, fraude COD | Signature + `fetchStatus`, idempotence, ledger immuable, réconciliation |
| **Delivery** | Fausse preuve, usurpation de position, détournement | Code de remise, photo horodatée + géo, contrôles de cohérence, suivi d'incidents |
| **Services** | Contournement hors plateforme, faux profils | Vérification, avis liés à l'interaction, signalements |
| **Immo** | **Fausses annonces / arnaques à l'avance**, photos volées | `VERIFIED` par revue humaine, détection de doublons d'images, avertissements, masquage de position exacte |
| **Jobs** | Fausses offres, collecte de CV, discrimination algorithmique | Vérification recruteur, contrôle d'accès aux CV, IA sans décision, attributs protégés retirés |
| **Agro** | Arnaques à l'acompte, faux acheteurs | Paiements encadrés, preuve de livraison, litiges |
| **Money** | Exposition de données financières perso | RLS utilisateur, consentement IA, chiffrement, masquage |
| **IA** | Injection de prompt, exfiltration, abus de coût, hallucination financière | Outils autorisés, contexte injecté serveur, ancrage des chiffres, quotas, validation de sortie |
| **Admin** | Menace interne, escalade de privilèges, compte staff compromis | Comptes séparés, SSO + MFA, 4-yeux, audit, accès tenant motivé/limité |
| **Mobile** | Appareil rooté, rétro-ingénierie, interception, données locales | SQLCipher, stockage sécurisé, obfuscation, attestation, TLS, aucune clé secrète |
| **Chaîne d'approvisionnement** | Dépendances compromises, secrets exposés | Lockfiles, scans, SBOM, secrets scanning, provenance |

Un **threat model STRIDE** par module est un livrable de la Definition of Done ([10 §8](10-testing.md)).

## 3. Contrôles techniques

### 3.1 Authentification et sessions
Voir [04](04-identity-access.md). Argon2id (mots de passe) ; HMAC pour les OTP ; SHA-256 pour les jetons stockés ; JWT asymétriques courts ; rotation des refresh ; révocation globale ; gestion des appareils ; MFA staff.

### 3.2 Autorisation
RBAC + politiques de ressource + RLS ; 404 plutôt que 403 pour ne pas révéler l'existence ; contrôle **de propriété sur chaque ressource** (BOLA) ; permissions sensibles séparées.

### 3.3 Validation et injection
Validation Zod stricte (rejet des champs inconnus, bornes, formats) ; **requêtes paramétrées uniquement** (aucune concaténation SQL) ; tris/filtres par **liste blanche** ; encodage des sorties ; **protection SSRF** (aucune récupération d'URL arbitraire côté serveur ; si nécessaire : liste blanche d'hôtes, résolution DNS contrôlée, blocage des plages privées) ; désérialisation sûre.

### 3.4 Téléversements
Types/tailles autorisés, **détection du vrai type MIME**, **antivirus** (ClamAV ou service tiers) **avant** disponibilité, nettoyage EXIF, ré-encodage des images, PDF/Office traités comme non fiables, stockage privé, URLs signées courtes, **nom d'objet généré** (jamais le nom fourni), quotas.

### 3.5 Limitation de débit et anti-abus
Couches : CDN/WAF → application (Redis) par IP/utilisateur/appareil/route/API key ; politiques renforcées : OTP, login, recherche, écriture, paiement, IA, messages ; détection de robots à l'inscription ; listes de blocage.

### 3.6 Cryptographie et secrets
- TLS 1.2+ partout, HSTS ; chiffrement au repos (volumes, buckets, sauvegardes) ; **chiffrement applicatif par enveloppe** pour documents d'identité et données très sensibles (clé maître en KMS/gestionnaire de secrets, rotation).
- **Aucun secret dans le dépôt** : gestionnaire de secrets par environnement, injection à l'exécution, **rotation** planifiée ; `gitleaks` en pre-commit **et** CI ; variables validées au démarrage.
- **Séparation stricte des environnements** : comptes cloud/projets, bases, projets FCM, clés PSP/SMS/LLM **distincts** ; jamais de credentials de production en dev.

### 3.7 CSRF, CORS, en-têtes
CSRF **pertinent uniquement pour l'admin** (cookies) : jetons + `SameSite=Strict` + contrôle d'origine ; API mobile par jeton Bearer (non concernée). CORS en liste blanche ; CSP stricte, `frame-ancestors 'none'`, `X-Content-Type-Options`, `Referrer-Policy`.

### 3.8 Mobile (MASVS)
Stockage sécurisé, SQLCipher, obfuscation, attestation d'intégrité sur endpoints sensibles, **pas de secret embarqué**, écrans sensibles masqués dans le sélecteur d'applications, journalisation sans PII, dépendances auditées, signature de release protégée (clés de signature dans un coffre, pas sur un poste).

### 3.9 Protection des données personnelles
- **Classification** (public / interne / personnel / sensible / financier) documentée par colonne ; **minimisation** (collecter le nécessaire) ; consentements versionnés ; **finalité** par usage ; **rétention** définie ; **export et effacement** outillés ; journal d'accès aux données sensibles.
- **Mineurs (Academy)** : traitements minimisés, consentement parental si requis, pas de publicité ciblée.
- **Conformité** : respecter la législation locale sur les données personnelles et sectorielle (paiement, immobilier, emploi) — **validation par un conseil juridique local** (hypothèse H7).

### 3.10 Journaux, audit, détection
- Logs applicatifs **expurgés** (téléphones, jetons, OTP, en-têtes d'autorisation, pièces KYC, contenu de messages, identifiants de paiement).
- **Audit append-only** (`ops.audit_logs`) : acteur, action, ressource, avant/après, IP/appareil, `request_id`, motif ; accès restreint ; option de **chaînage de hachage** pour détecter l'altération.
- Détection : alertes sur pics d'échecs d'auth/OTP, création massive de comptes, accès admin inhabituels, exports volumineux, divergences de paiement.

## 4. Sécurité du cycle de vie (SDLC)

| Étape | Contrôle |
|---|---|
| Conception | Threat model ; revue d'architecture pour toute nouvelle dépendance de module ou nouveau fournisseur externe |
| Code | Revue obligatoire (CODEOWNERS sur `contracts/`, migrations, `payments`, `auth`, `rbac`) ; règles de lint sécurité |
| CI | SAST (CodeQL/Semgrep), scan de dépendances (Dependabot/Renovate + audit), **scan de secrets**, scan de conteneurs (Trivy), **SBOM**, lint de schéma RLS |
| Staging | **DAST** (OWASP ZAP), Schemathesis, tests d'autorisation |
| Production | WAF, rate limiting, alertes, audit ; **revue d'accès trimestrielle** |
| Périodique | **Test d'intrusion externe** avant le jalon « public v1 » (fin Phase 4) et avant Phase 11 ; programme de divulgation (`security.txt`), *bug bounty* ultérieur |

## 5. Réponse aux incidents
- **Runbooks** : compromission de compte, fuite de données, PSP défaillant, dérive de réconciliation, abus SMS, injection IA, clé compromise.
- **Rotation d'urgence** de tous les secrets documentée et **répétée** ; révocation de sessions à grande échelle possible (`token_version`, JWKS).
- Notification des personnes/autorités concernées selon les obligations locales ; post-mortem sans recherche de coupable.

## 6. Sauvegardes et continuité
PITR (WAL) + snapshots quotidiens + copie inter-région ; versioning du stockage objet ; Redis persistant pour les files ; **test de restauration trimestriel** ; exercice de reprise annuel (Phase 11) ; cibles indicatives **RPO ≤ 5 min / RTO ≤ 1 h**.

## 7. Règles de journalisation — exemples de champs interdits
`Authorization`, `Cookie`, `refresh_token`, `otp`, `code`, `password`, `phone` (masquer : `+224 6•• ••• 45`), contenu de `messages`, `verification_documents`, numéros de compte/mobile money complets, prompts contenant des données personnelles (les stocker seulement dans les tables dédiées, expurgés).
