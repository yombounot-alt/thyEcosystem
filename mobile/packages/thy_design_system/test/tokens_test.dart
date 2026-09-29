import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_design_system/thy_design_system.dart';

/// Tokens THY (lot L0.9) : le Dart généré correspond à shared/design-tokens/tokens.json (jamais
/// modifié à la main) et chaque paire texte/fond tient le contraste WCAG dans les deux modes.
void main() {
  final tokens =
      jsonDecode(File('../../../shared/design-tokens/tokens.json').readAsStringSync())
          as Map<String, dynamic>;

  Map<String, Color> semantic(String mode) => {
    for (final e in (tokens['semantic'][mode] as Map<String, dynamic>).entries)
      if (!e.key.startsWith(r'$'))
        e.key: Color(int.parse('FF${(e.value as String).substring(1)}', radix: 16)),
  };

  Map<String, Color> generated(ThyColors c) => {
    'background': c.background,
    'surface': c.surface,
    'surfaceRaised': c.surfaceRaised,
    'border': c.border,
    'onSurface': c.onSurface,
    'onSurfaceMuted': c.onSurfaceMuted,
    'primary': c.primary,
    'onPrimary': c.onPrimary,
    'primaryContainer': c.primaryContainer,
    'onPrimaryContainer': c.onPrimaryContainer,
    'accent': c.accent,
    'accentText': c.accentText,
    'onAccent': c.onAccent,
    'success': c.success,
    'successContainer': c.successContainer,
    'warning': c.warning,
    'warningContainer': c.warningContainer,
    'danger': c.danger,
    'dangerContainer': c.dangerContainer,
    'info': c.info,
    'focusRing': c.focusRing,
  };

  double luminance(Color c) {
    double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) * 1.0;
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double contrast(Color a, Color b) {
    final l1 = luminance(a), l2 = luminance(b);
    return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
  }

  group('tokens', () {
    test('the generated Dart matches tokens.json (never edited by hand)', () {
      for (final (mode, colors) in [('light', ThyColors.light), ('dark', ThyColors.dark)]) {
        expect(generated(colors), semantic(mode), reason: 'mode $mode — relancer build.mjs');
      }
    });

    test('every text/background pair meets WCAG in both modes', () {
      final pairs = tokens['contrast'] as Map<String, dynamic>;
      final failures = <String>[];
      for (final (kind, minimum) in [('text', 4.5), ('ui', 3.0)]) {
        for (final pair in pairs[kind] as List<dynamic>) {
          final [fg, bg] = (pair as List<dynamic>).cast<String>();
          for (final (mode, colors) in [('clair', ThyColors.light), ('sombre', ThyColors.dark)]) {
            final map = generated(colors);
            final ratio = contrast(map[fg]!, map[bg]!);
            if (ratio < minimum) failures.add('$mode $fg/$bg ${ratio.toStringAsFixed(2)}');
          }
        }
      }
      expect(failures, isEmpty);
    });

    test('gold is never a text colour on white (charte §2.2)', () {
      expect(contrast(ThyColors.light.accent, ThyColors.light.background), lessThan(3));
      expect(contrast(ThyColors.light.accentText, ThyColors.light.background), greaterThan(4.5));
    });
  });

  group('theme', () {
    test('the primary call to action is royal blue with white text (charte §5)', () {
      final light = AppTheme.light();
      expect(light.colorScheme.primary, ThyPalette.blue700);
      expect(light.colorScheme.onPrimary, ThyPalette.slateWhite);
      expect(light.extension<ThyColors>(), ThyColors.light);
      expect(AppTheme.dark().extension<ThyColors>(), ThyColors.dark);
      expect(AppTheme.dark().brightness, Brightness.dark);
    });
  });
}
