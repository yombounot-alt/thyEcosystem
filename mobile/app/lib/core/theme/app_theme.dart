import 'package:flutter/material.dart';

import 'thy_tokens.g.dart';

export 'thy_tokens.g.dart' show ThyColors, ThyPalette;

/// `context.colors.primary` : la couleur sémantique du mode (clair/sombre) en cours. Les écrans
/// n'utilisent QUE ces couleurs — jamais un hexadécimal en dur (vérifié par
/// test/design_system_test.dart). Valeurs : shared/design-tokens/tokens.json.
extension ThyColorsContext on BuildContext {
  ThyColors get colors => Theme.of(this).extension<ThyColors>() ?? ThyColors.light;
}

/// Voiles posés sur une image caméra ou une photo : noirs translucides dans les DEUX modes (la
/// caméra est toujours sombre) — seules couleurs non issues des tokens de marque, et définies ici.
abstract final class ThyScrims {
  static const camera = Color(0xCC000000);
  static const cameraFade = Color(0x00000000);
  static const photoPlaceholder = Color(0x11000000);
}

/// Thèmes THY clair et sombre, construits sur les tokens de la charte (docs/brand/README.md §4).
/// Aplats par défaut ; l'or reste un accent décoratif (jamais une couleur de texte, sauf
/// `accentText`).
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(ThyColors.light, Brightness.light);

  static ThemeData dark() => _build(ThyColors.dark, Brightness.dark);

  static ThemeData _build(ThyColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      secondary: c.accent,
      onSecondary: c.onAccent,
      tertiary: c.accentText,
      onTertiary: c.background,
      error: c.danger,
      onError: brightness == Brightness.light ? ThyPalette.slateWhite : c.background,
      errorContainer: c.dangerContainer,
      onErrorContainer: c.danger,
      surface: c.background,
      onSurface: c.onSurface,
      onSurfaceVariant: c.onSurfaceMuted,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.border,
      outlineVariant: c.border,
    );

    final radius12 = BorderRadius.circular(12);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
      dividerColor: c.border,
      textTheme: TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: c.onSurface),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, color: c.onSurface),
        bodyMedium: TextStyle(color: c.onSurface),
        bodySmall: TextStyle(color: c.onSurfaceMuted),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: c.background,
        foregroundColor: c.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: c.border),
        ),
        // Anneau de focus visible (charte §4 `focusRing`) : clavier, lecteur d'écran.
        focusedBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: c.focusRing, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: c.danger),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: radius12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primary,
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(borderRadius: radius12),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceRaised,
        indicatorColor: c.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating),
      badgeTheme: BadgeThemeData(backgroundColor: c.danger, textColor: c.background),
    );
  }
}
