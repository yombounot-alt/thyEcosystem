import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/providers.dart';
import 'package:thy_app/features/auth/application/auth_controller.dart';
import 'package:thy_app/features/auth/presentation/onboarding_screen.dart';
import 'package:thy_app/features/auth/presentation/phone_screen.dart';
import 'package:thy_app/l10n/app_localizations.dart';

import 'fakes.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

Set<String> _placeholders(String message) =>
    RegExp(r'\{(\w+)\}').allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  group('translations', () {
    final fr = _arb('fr');
    final en = _arb('en');

    test('English has exactly the French keys (no missing, no leftover translation)', () {
      expect(_messageKeys(en), _messageKeys(fr));
    });

    test('every translation keeps the same placeholders', () {
      for (final key in _messageKeys(fr)) {
        expect(_placeholders(en[key] as String), _placeholders(fr[key] as String), reason: key);
      }
    });

    test('no empty text', () {
      for (final arb in [fr, en]) {
        for (final key in _messageKeys(arb)) {
          expect((arb[key] as String).trim(), isNotEmpty, reason: key);
        }
      }
    });
  });

  Future<void> pumpIn(WidgetTester tester, Locale locale, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authApiProvider.overrideWithValue(FakeAuthApi()),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the sign-in screens read their texts from the translations', (tester) async {
    await pumpIn(tester, const Locale('en'), const PhoneScreen());
    expect(find.text('Your number'), findsOneWidget);
    expect(find.text('Get the code'), findsOneWidget);

    await pumpIn(tester, const Locale('fr'), const PhoneScreen());
    expect(find.text('Votre numéro'), findsOneWidget);
    expect(find.text('Recevoir le code'), findsOneWidget);
  });

  testWidgets('onboarding only promises what the app does (no AI assistant yet)', (tester) async {
    await pumpIn(tester, const Locale('fr'), const OnboardingScreen());
    expect(find.textContaining('IA'), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(find.text('Vendez même sans connexion'), findsOneWidget);
  });
}
