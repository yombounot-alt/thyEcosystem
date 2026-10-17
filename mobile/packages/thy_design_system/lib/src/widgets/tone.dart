import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Ton d'un message ou d'un statut. Chaque ton associe une couleur de texte à son fond, en ne
/// prenant que des paires dont le contraste WCAG est vérifié par `shared/design-tokens` dans les
/// deux modes : jamais une couleur d'état posée sur un fond transparent.
enum ThyTone { neutral, info, success, warning, danger }

/// Couleurs (texte/icône, fond) d'un [ThyTone] dans le thème en cours.
({Color foreground, Color background}) toneColors(BuildContext context, ThyTone tone) {
  final c = context.colors;
  return switch (tone) {
    ThyTone.neutral => (foreground: c.onSurfaceMuted, background: c.surface),
    ThyTone.info => (foreground: c.onPrimaryContainer, background: c.primaryContainer),
    ThyTone.success => (foreground: c.success, background: c.successContainer),
    ThyTone.warning => (foreground: c.warning, background: c.warningContainer),
    ThyTone.danger => (foreground: c.danger, background: c.dangerContainer),
  };
}
