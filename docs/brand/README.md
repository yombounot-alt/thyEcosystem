# THY — Identité visuelle et tokens de design (proposition dérivée du logo)

> Source : logo fourni le 2026-09-22 → [thy-business-logo.png](thy-business-logo.png) (PNG raster 1774×887, fond blanc).
> **Le logo n'est pas modifié.** Ce document en déduit les tokens du design system (lot L0.9 de la Phase 0).
> Les couleurs marquées « échantillonnée » ont été mesurées sur les pixels du PNG ; les autres (échelles) sont **interpolées et à valider** par le design. **Les valeurs officielles (fichier source vectoriel) prévalent** dès qu'elles sont disponibles.

---

## 1. Anatomie du logo

| Élément         | Description                                                                                                    |
| --------------- | -------------------------------------------------------------------------------------------------------------- |
| **Monogramme**  | « T » et « H » imbriqués en volume (cube/toit) : faces bleu marine, **arête supérieure et barre basse dorées** |
| **Wordmark**    | « THY » en capitales très grasses, bleu marine                                                                 |
| **Sous-marque** | « Business » en graisse normale, séparé par un **filet vertical doré**                                         |
| **Signature**   | « Construire. Connecter. Grandir. » en doré, espacée                                                           |

**Observation structurante** : le logo est un lockup **`THY | Business`**. Ce format est un système de marque prêt à l'emploi : même monogramme, même filet, seul le nom de module change (`THY | Marketplace`, `THY | Services`, …). Cela colle à l'architecture « une seule app, dix modules ».

**Décision (2026-09-22) : pas de fichier vectoriel source disponible.** On avance avec le PNG raster. Conséquences pratiques :

- Un **monogramme carré 1024×1024** a été extrait mécaniquement du PNG (recadrage de la zone du monogramme, fond blanc, zone de sécurité ~12 %, aucune recoloration) : [assets/monogram-icon-source-1024.png](assets/monogram-icon-source-1024.png). C'est la **source suffisante** pour générer les icônes d'application (Android/iOS acceptent une source PNG haute résolution via `flutter_launcher_icons` — le vectoriel n'est pas strictement requis pour ça).
- Ce qui **reste bloqué** sans vectoriel : une icône **monochrome** parfaitement nette (Android 13 « themed icon »), une **version inversée** pour fond sombre (le marine `#002B6C` est quasi invisible sur fond sombre — nécessite un vrai retravail par un designer, pas une simple recoloration automatique d'un raster), et tout support imprimé/grand format. **Reste une tâche pour le designer du logo**, non substituable par un recadrage.
- **Autres éléments à produire par le designer**, indépendamment du vectoriel : **lockup maître « THY »** seul (sans « Business ») pour l'écran d'accueil/splash/nom de l'app — « THY | Business » reste le lockup du module Business ; **police de marque** à confirmer (hypothèse retenue : sans-serif géométrique type _Montserrat_, à valider).

---

## 2. Couleurs de marque

### 2.1 Échantillonnées sur le logo

| Rôle           | Hex                                | Usage dans le logo                            |
| -------------- | ---------------------------------- | --------------------------------------------- |
| **Marine**     | `#002B6C`                          | Wordmark « THY », faces sombres du monogramme |
| Bleu profond   | `#003988`                          | Faces intermédiaires                          |
| **Bleu royal** | `#004CB2` (→ `#0060C0` en dégradé) | Flèche du « Y », faces éclairées              |
| **Or**         | `#CD9311`                          | Filet vertical, signature, barre basse        |
| Or lumière     | `#EBB33F` → `#F0C048`              | Reflet de l'arête supérieure                  |

Le logo utilise des **dégradés** (marine→royal, or métallique). Dans l'UI : **aplats par défaut** ; dégradés réservés aux moments de marque (splash, en-tête d'onboarding) — meilleure performance et accessibilité.

### 2.2 Contraste mesuré (WCAG, calculé)

| Combinaison                                  | Ratio       | Verdict                                                                             |
| -------------------------------------------- | ----------- | ----------------------------------------------------------------------------------- |
| Marine `#002B6C` sur blanc                   | 13,4 : 1    | ✅ AAA                                                                              |
| Royal `#004CB2` sur blanc                    | 7,85 : 1    | ✅ AAA (bouton primaire : texte blanc sur royal)                                    |
| **Or `#CD9311` sur blanc**                   | **2,7 : 1** | ❌ **interdit pour du texte** (décoratif / grands aplats / icônes uniquement)       |
| Or foncé `#946809` sur blanc                 | 4,95 : 1    | ✅ AA — **couleur de texte « or »**                                                 |
| Marine sur or `#CD9311`                      | 4,98 : 1    | ✅ AA — **bouton doré = texte marine**, jamais blanc                                |
| Marine sur or clair `#EBB33F`                | 7,08 : 1    | ✅                                                                                  |
| Bleu 400 `#5C9CF0` sur fond sombre `#0B1220` | 6,66 : 1    | ✅ primaire en mode sombre                                                          |
| Blanc sur bleu 500 `#2F7FE0`                 | 4,01 : 1    | ❌ pas de texte blanc sur ce bleu → bouton sombre = fond bleu 400 + texte `#0B1220` |

**Règle** : jamais de texte doré `#CD9311` ; l'or sert d'**accent** (filets, badges, icônes, mises en avant) et de **fond de bouton secondaire à texte marine**.

---

## 3. Tokens primitifs (à générer en JSON → Dart + CSS)

### Bleu (dérivé du marine/royal)

| Token        | Hex           |     | Token    | Hex       |
| ------------ | ------------- | --- | -------- | --------- |
| blue-950     | `#001A45`     |     | blue-400 | `#5C9CF0` |
| **blue-900** | **`#002B6C`** |     | blue-300 | `#8FBBF7` |
| blue-800     | `#003988`     |     | blue-200 | `#BCD5FB` |
| **blue-700** | **`#004CB2`** |     | blue-100 | `#E0ECFD` |
| blue-600     | `#0060C0`     |     | blue-50  | `#F0F6FE` |
| blue-500     | `#2F7FE0`     |     |          |           |

### Or (dérivé de `#CD9311`)

| Token        | Hex           |     | Token    | Hex       |
| ------------ | ------------- | --- | -------- | --------- |
| gold-900     | `#5E4306`     |     | gold-400 | `#EBB33F` |
| gold-800     | `#7A5606`     |     | gold-300 | `#F3CB70` |
| **gold-700** | **`#946809`** |     | gold-200 | `#F8E0A5` |
| gold-600     | `#B07F0E`     |     | gold-100 | `#FCF1D6` |
| **gold-500** | **`#CD9311`** |     | gold-50  | `#FEF9EC` |

### Neutres (bleutés, cohérents avec la marque)

`slate-950 #0B1220` · `slate-900 #0B1730` · `slate-850 #121B2E` · `slate-800 #182338` · `slate-700 #2A3752` · `slate-600 #5B6B85` · `slate-400 #A9B6CC` · `slate-300 #D9E0EC` · `slate-200 #E6ECF5` · `slate-100 #F5F7FB` · `white #FFFFFF`

---

## 4. Tokens sémantiques

| Token                         | Clair                       | Sombre             | Note                                                |
| ----------------------------- | --------------------------- | ------------------ | --------------------------------------------------- |
| `background`                  | `#FFFFFF`                   | `#0B1220`          |                                                     |
| `surface`                     | `#F5F7FB`                   | `#121B2E`          | cartes, champs                                      |
| `surfaceRaised`               | `#FFFFFF`                   | `#182338`          | modales, feuilles                                   |
| `border`                      | `#D9E0EC`                   | `#2A3752`          |                                                     |
| `onSurface` (texte principal) | `#0B1730` (17,8:1)          | `#E6ECF5` (15,8:1) |                                                     |
| `onSurfaceMuted` (secondaire) | `#5B6B85` (5,4:1)           | `#A9B6CC` (9,1:1)  |                                                     |
| `primary`                     | `#004CB2`                   | `#5C9CF0`          | CTA principal                                       |
| `onPrimary`                   | `#FFFFFF`                   | `#0B1220`          |                                                     |
| `primaryContainer`            | `#E0ECFD`                   | `#002B6C`          | fonds tintés                                        |
| `accent` (or)                 | `#CD9311`                   | `#EBB33F`          | filets, badges, icônes — **pas de texte**           |
| `accentText`                  | `#946809`                   | `#EBB33F`          | texte « or » accessible                             |
| `onAccent`                    | `#002B6C`                   | `#0B1220`          | texte sur bouton or                                 |
| `success` / bg                | `#0F7A4A` / `#E4F5EC`       | `#4CC38A` / —      | 5,4:1 (clair) · 8,5:1 (sombre)                      |
| `warning` / bg                | `#7A5606` / `#FCF1D6`       | `#EBB33F` / —      | **or-800** en texte : or-700 sur or-100 = 4,41:1 ❌ |
| `danger` / bg                 | `#B42318` / `#FDECEA`       | `#FF8A80` / —      | 6,6:1 (clair) · 8,2:1 (sombre)                      |
| `info`                        | `#004CB2`                   | `#5C9CF0`          |                                                     |
| `focusRing`                   | `#004CB2` (2 px + décalage) | `#8FBBF7`          | visibilité clavier/lecteur                          |

Les paires « texte sur fond » ci-dessus sont **testées automatiquement** en CI (test de contraste ≥ 4,5:1 texte, ≥ 3:1 composants graphiques) — un token qui casse le seuil fait échouer la build.

## 5. Règles d'usage

- **CTA principal** = royal (`primary`) + texte blanc ; **un seul CTA principal par écran**.
- **Or** = accent premium/repère (badges, filets, états « mis en avant »), jamais porteur de sens seul (toujours doublé d'une icône ou d'un texte).
- **Badge de vérification** : forme et icône **dédiées**, distinctes de tout autre badge ; utilisé **uniquement** pour un statut `VERIFIED` réel. La couleur sera fixée en L0.9. « Numéro confirmé » (OTP) garde un style neutre distinct.
- **Accent par module** : décidé en L0.9 après essai sur la galerie ; contrainte : famille bleu/or + 3–4 teintes complémentaires modérées, jamais en concurrence avec le CTA principal, contraste vérifié dans les 2 modes.
- **Typographie** : police de marque à confirmer (§1). Approche proposée : **une police de titres alignée sur le wordmark** + police de texte très lisible ; **variables + sous-ensemble Latin** pour limiter le poids (budget de performance Android modeste).
- **Iconographie** : jeu unique, traits homogènes, taille tactile ≥ 48 dp.
- **Écrans sensibles** (paiement, finance) : sobriété, pas d'or décoratif.

## 6. Intégration technique (Phase 0, lot L0.9)

```
shared/design-tokens/
  tokens/primitives.json    ← §3
  tokens/semantic.light.json / semantic.dark.json   ← §4
  assets/brand/             ← logos, icônes (SVG source requis)
  style-dictionary.config   → Dart (ThemeExtension) + CSS variables (admin)
```

Un lint interdit toute couleur/espacement « en dur » dans le code Flutter et React.
