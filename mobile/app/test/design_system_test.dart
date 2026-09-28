import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/theme/app_theme.dart';

import 'fakes.dart';

/// Design system THY (lot L0.9) : les tokens générés correspondent à la source, les contrastes
/// tiennent dans les deux modes, aucune couleur n'est codée en dur dans les écrans, et l'app
/// entière fonctionne en mode sombre.
void main() {
  final tokens =
      jsonDecode(File('../../shared/design-tokens/tokens.json').readAsStringSync())
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

  group('no hard-coded colours in the screens', () {
    // Seul le dossier du thème définit des couleurs. Exceptions assumées : le reçu PDF (impression
    // noir et blanc, indépendante du thème) et l'écran caméra (toujours sombre : blanc/noir).
    const allowed = {'lib/core/theme/', 'lib/features/sales/application/receipt_pdf.dart'};
    final hex = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
    final named = RegExp(
      r'Colors\.(red|green|blue|orange|amber|grey|yellow|purple|teal|pink|indigo|cyan|brown|lime|deep\w+|light\w+)',
    );
    final blackOrWhite = RegExp(r'Colors\.(white|black)');

    Iterable<(String, int, String)> offending(bool Function(String path, String line) bad) sync* {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart') || allowed.any(path.startsWith)) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (bad(path, lines[i])) yield (path, i + 1, lines[i].trim());
        }
      }
    }

    test('no hexadecimal colour and no named Material hue', () {
      final found = offending((_, line) => hex.hasMatch(line) || named.hasMatch(line));
      expect(found.map((f) => '${f.$1}:${f.$2}  ${f.$3}'), isEmpty);
    });

    test('pure white/black only on the camera screen (always dark)', () {
      final found = offending(
        (path, line) =>
            blackOrWhite.hasMatch(line) && !path.endsWith('core/scanning/barcode_scan_screen.dart'),
      );
      expect(found.map((f) => '${f.$1}:${f.$2}  ${f.$3}'), isEmpty);
    });
  });

  group('dark mode', () {
    testWidgets('follows the phone: the whole app renders with the dark tokens', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpAuthenticatedApp(tester);

      final dashboard = tester.widget<Scaffold>(find.byType(Scaffold).first);
      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(context.colors, ThyColors.dark);
      expect(
        dashboard.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
        ThyColors.dark.background,
      );

      // Every main tab and a few secondary screens render without layout or theme errors.
      for (final tab in ['Caisse', 'Stock', 'Plus', 'Accueil']) {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')),
      );
      await tester.pumpAndSettle();
      for (final entry in ['Mon offre', 'Équipe']) {
        await tester.ensureVisible(find.text(entry));
        await tester.tap(find.text(entry));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: entry);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('light mode stays the default when the phone is light', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpAuthenticatedApp(tester);
      final context = tester.element(find.byType(Scaffold).first);
      expect(context.colors, ThyColors.light);
      // Primary CTA = royal blue with white text (charte §5).
      expect(Theme.of(context).colorScheme.primary, ThyPalette.blue700);
      expect(Theme.of(context).colorScheme.onPrimary, ThyPalette.slateWhite);
    });
  });
}
