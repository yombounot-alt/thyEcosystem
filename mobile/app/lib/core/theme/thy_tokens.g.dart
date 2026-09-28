// GÉNÉRÉ par shared/design-tokens/build.mjs depuis tokens.json — NE PAS MODIFIER À LA MAIN.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

/// Primitives de la marque THY (docs/brand/README.md §3). Préférer les couleurs sémantiques
/// ([ThyColors]) dans les écrans : seules elles s'adaptent au mode sombre.
abstract final class ThyPalette {
  static const blue50 = Color(0xFFF0F6FE);
  static const blue100 = Color(0xFFE0ECFD);
  static const blue200 = Color(0xFFBCD5FB);
  static const blue300 = Color(0xFF8FBBF7);
  static const blue400 = Color(0xFF5C9CF0);
  static const blue500 = Color(0xFF2F7FE0);
  static const blue600 = Color(0xFF0060C0);
  static const blue700 = Color(0xFF004CB2);
  static const blue800 = Color(0xFF003988);
  static const blue900 = Color(0xFF002B6C);
  static const blue950 = Color(0xFF001A45);
  static const gold50 = Color(0xFFFEF9EC);
  static const gold100 = Color(0xFFFCF1D6);
  static const gold200 = Color(0xFFF8E0A5);
  static const gold300 = Color(0xFFF3CB70);
  static const gold400 = Color(0xFFEBB33F);
  static const gold500 = Color(0xFFCD9311);
  static const gold600 = Color(0xFFB07F0E);
  static const gold700 = Color(0xFF946809);
  static const gold800 = Color(0xFF7A5606);
  static const gold900 = Color(0xFF5E4306);
  static const slate100 = Color(0xFFF5F7FB);
  static const slate200 = Color(0xFFE6ECF5);
  static const slate300 = Color(0xFFD9E0EC);
  static const slate400 = Color(0xFFA9B6CC);
  static const slate600 = Color(0xFF5B6B85);
  static const slate700 = Color(0xFF2A3752);
  static const slate800 = Color(0xFF182338);
  static const slate850 = Color(0xFF121B2E);
  static const slate900 = Color(0xFF0B1730);
  static const slate950 = Color(0xFF0B1220);
  static const slateWhite = Color(0xFFFFFFFF);
}

/// Couleurs sémantiques THY (docs/brand/README.md §4), une valeur par mode. Accès :
/// `context.colors.primary` (voir app_theme.dart).
@immutable
class ThyColors extends ThemeExtension<ThyColors> {
  const ThyColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.info,
    required this.focusRing,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color accent;
  final Color accentText;
  final Color onAccent;
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color info;
  final Color focusRing;

  static const light = ThyColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F7FB),
    surfaceRaised: Color(0xFFFFFFFF),
    border: Color(0xFFD9E0EC),
    onSurface: Color(0xFF0B1730),
    onSurfaceMuted: Color(0xFF5B6B85),
    primary: Color(0xFF004CB2),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE0ECFD),
    onPrimaryContainer: Color(0xFF002B6C),
    accent: Color(0xFFCD9311),
    accentText: Color(0xFF946809),
    onAccent: Color(0xFF002B6C),
    success: Color(0xFF0F7A4A),
    successContainer: Color(0xFFE4F5EC),
    warning: Color(0xFF7A5606),
    warningContainer: Color(0xFFFCF1D6),
    danger: Color(0xFFB42318),
    dangerContainer: Color(0xFFFDECEA),
    info: Color(0xFF004CB2),
    focusRing: Color(0xFF004CB2),
  );

  static const dark = ThyColors(
    background: Color(0xFF0B1220),
    surface: Color(0xFF121B2E),
    surfaceRaised: Color(0xFF182338),
    border: Color(0xFF2A3752),
    onSurface: Color(0xFFE6ECF5),
    onSurfaceMuted: Color(0xFFA9B6CC),
    primary: Color(0xFF5C9CF0),
    onPrimary: Color(0xFF0B1220),
    primaryContainer: Color(0xFF002B6C),
    onPrimaryContainer: Color(0xFFE0ECFD),
    accent: Color(0xFFEBB33F),
    accentText: Color(0xFFEBB33F),
    onAccent: Color(0xFF0B1220),
    success: Color(0xFF4CC38A),
    successContainer: Color(0xFF12301F),
    warning: Color(0xFFEBB33F),
    warningContainer: Color(0xFF3A2A06),
    danger: Color(0xFFFF8A80),
    dangerContainer: Color(0xFF3D1512),
    info: Color(0xFF5C9CF0),
    focusRing: Color(0xFF8FBBF7),
  );

  @override
  ThyColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? accent,
    Color? accentText,
    Color? onAccent,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? info,
    Color? focusRing,
  }) {
    return ThyColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      info: info ?? this.info,
      focusRing: focusRing ?? this.focusRing,
    );
  }

  @override
  ThyColors lerp(ThemeExtension<ThyColors>? other, double t) {
    if (other is! ThyColors) return this;
    return ThyColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
    );
  }
}
