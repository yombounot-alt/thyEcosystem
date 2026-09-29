import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_design_system/thy_design_system.dart';

import 'fakes.dart';

/// Design system THY appliqué à l'app (lot L0.9) : aucune couleur n'est codée en dur dans les
/// écrans, et l'app entière fonctionne en mode sombre. Les tokens et leur contraste sont testés
/// dans le paquet (mobile/packages/thy_design_system/test).
void main() {
  group('no hard-coded colours in the screens', () {
    // Seul le paquet design system définit des couleurs. Exceptions assumées : le reçu PDF
    // (impression noir et blanc, indépendante du thème) et l'écran caméra (toujours sombre).
    // Le socle `thy_core` est parcouru aussi : ses écrans (caméra) suivent la même règle.
    const roots = ['lib', '../packages/thy_core/lib'];
    const allowed = {'lib/features/sales/application/receipt_pdf.dart'};
    final hex = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
    final named = RegExp(
      r'Colors\.(red|green|blue|orange|amber|grey|yellow|purple|teal|pink|indigo|cyan|brown|lime|deep\w+|light\w+)',
    );
    final blackOrWhite = RegExp(r'Colors\.(white|black)');

    Iterable<(String, int, String)> offending(bool Function(String path, String line) bad) sync* {
      for (final f in [
        for (final root in roots) ...Directory(root).listSync(recursive: true).whereType<File>(),
      ]) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart') || allowed.any(path.startsWith)) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (bad(path, lines[i])) yield (path, i + 1, lines[i].trim());
        }
      }
    }

    test('the scan covers the app and thy_core (guards against a silently empty check)', () {
      final files = offending((_, _) => true).map((f) => f.$1).toSet();
      expect(files, contains('../packages/thy_core/lib/src/scanning/barcode_scan_screen.dart'));
      expect(files, contains('lib/features/shell/presentation/more_screen.dart'));
    });

    test('no hexadecimal colour and no named Material hue', () {
      final found = offending((_, line) => hex.hasMatch(line) || named.hasMatch(line));
      expect(found.map((f) => '${f.$1}:${f.$2}  ${f.$3}'), isEmpty);
    });

    test('pure white/black only on the camera screen (always dark)', () {
      final found = offending(
        (path, line) =>
            blackOrWhite.hasMatch(line) && !path.endsWith('scanning/barcode_scan_screen.dart'),
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
