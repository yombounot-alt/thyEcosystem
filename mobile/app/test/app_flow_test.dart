import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/app.dart';
import 'package:thy_app/core/providers.dart';
import 'package:thy_app/features/auth/application/auth_controller.dart';
import 'package:thy_app/features/dashboard/application/dashboard_providers.dart';

import 'fakes.dart';

void main() {
  testWidgets('unauthenticated user lands on the onboarding screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tokenStorageProvider.overrideWithValue(FakeTokenStorage())],
        child: const ThyBusinessApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gérez votre commerce simplement'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
  });

  Future<FakeAuthApi> pumpSignedOutApp(WidgetTester tester, {FakeAuthApi? auth}) async {
    final api = auth ?? FakeAuthApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authApiProvider.overrideWithValue(api),
          dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
        ],
        child: const ThyBusinessApp(),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  Future<void> openPhoneScreen(WidgetTester tester) async {
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
  }

  /// On the phone screen: types the number, ticks the terms (unless told not to) and asks for a code.
  Future<void> submitPhone(WidgetTester tester, String phone, {bool acceptTerms = true}) async {
    await tester.enterText(find.byType(TextFormField), phone);
    if (acceptTerms) {
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(ElevatedButton, 'Recevoir le code'));
    await tester.pumpAndSettle();
  }

  testWidgets('signing in with a phone number and a code leads to the dashboard', (tester) async {
    final auth = await pumpSignedOutApp(tester);

    // Sign-up and sign-in are one flow: no password, no separate "create account".
    await openPhoneScreen(tester);
    expect(find.text('Mot de passe'), findsNothing);

    await submitPhone(tester, '+224600000000');
    expect(auth.requestedPhones, ['+224600000000']);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Vérifier'));
    await tester.pumpAndSettle();

    expect(auth.triedCodes, ['123456']);
    expect(find.textContaining('Bonjour, Tamba'), findsOneWidget);
    expect(find.text('Boutique Demo'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('no code is requested until the terms are accepted', (tester) async {
    final auth = await pumpSignedOutApp(tester);
    await openPhoneScreen(tester);
    await submitPhone(tester, '+224600000000', acceptTerms: false);

    expect(auth.requestedPhones, isEmpty);
    expect(find.textContaining('accepter les conditions'), findsWidgets);
  });

  testWidgets('a malformed phone number is refused before any code is requested', (tester) async {
    final auth = await pumpSignedOutApp(tester);
    await openPhoneScreen(tester);
    await submitPhone(tester, '0600000000');

    expect(find.textContaining('Numéro invalide'), findsOneWidget);
    expect(auth.requestedPhones, isEmpty);
  });

  testWidgets('a first sign-in asks the name once, then goes on to the dashboard', (tester) async {
    final auth = FakeAuthApi(fullName: null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage(access: 'a', refresh: 'r')),
          authApiProvider.overrideWithValue(auth),
          dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
        ],
        child: const ThyBusinessApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comment vous appelez-vous ?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Tamba Camara');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continuer'));
    await tester.pumpAndSettle();

    expect(auth.fullName, 'Tamba Camara');
    expect(find.textContaining('Bonjour, Tamba'), findsOneWidget);
  });

  testWidgets('a restored session goes straight to the dashboard and can log out', (tester) async {
    await pumpAuthenticatedApp(tester);
    expect(find.textContaining('Bonjour, Tamba'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Déconnexion'));
    await tester.pumpAndSettle();

    expect(find.text('Commencer'), findsOneWidget);
  });
}
