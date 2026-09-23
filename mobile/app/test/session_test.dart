import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/api/api_exception.dart';
import 'package:thy_app/core/storage/local_store.dart';

import 'fakes.dart';

/// Opening the app is the moment offline mode matters most: signing in again needs the network.
void main() {
  final noNetwork = ApiException(
    'Impossible de contacter le serveur. Vérifiez votre connexion.',
    isConnectionProblem: true,
  );

  group('opening the app', () {
    testWidgets('with no network, the user stays signed in and can retry', (tester) async {
      final tokens = FakeTokenStorage(access: 'a', refresh: 'r');
      final auth = FakeAuthApi()..meError = noNetwork;

      await pumpAuthenticatedApp(tester, authApi: auth, tokenStorage: tokens);

      expect(find.textContaining('Impossible de joindre le serveur'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('Commencer'), findsNothing, reason: 'not thrown back to the onboarding');
      expect(await tokens.readAccessToken(), 'a', reason: 'the session is kept');
      expect(await tokens.readRefreshToken(), 'r');

      // The network is back.
      auth.meError = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('a server having a bad day (5xx) does not sign anyone out either', (tester) async {
      final tokens = FakeTokenStorage(access: 'a', refresh: 'r');
      final auth = FakeAuthApi()..meError = ApiException('Erreur interne', statusCode: 503);

      await pumpAuthenticatedApp(tester, authApi: auth, tokenStorage: tokens);

      expect(find.text('Réessayer'), findsOneWidget);
      expect(await tokens.readRefreshToken(), 'r');
    });

    testWidgets('a session the server refuses (401) sends the user back to sign in', (
      tester,
    ) async {
      final tokens = FakeTokenStorage(access: 'a', refresh: 'r');
      final auth = FakeAuthApi()..meError = ApiException('Session expirée', statusCode: 401);

      await pumpAuthenticatedApp(tester, authApi: auth, tokenStorage: tokens);

      expect(find.text('Commencer'), findsOneWidget);
      expect(await tokens.readAccessToken(), isNull);
      expect(await tokens.readRefreshToken(), isNull);
    });

    testWidgets('the splash offers a way out when the session cannot be restored', (tester) async {
      final tokens = FakeTokenStorage(access: 'a', refresh: 'r');
      final auth = FakeAuthApi()..meError = noNetwork;

      await pumpAuthenticatedApp(tester, authApi: auth, tokenStorage: tokens);
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();

      expect(find.text('Commencer'), findsOneWidget);
      expect(await tokens.readRefreshToken(), isNull);
    });
  });

  group('signing in', () {
    testWidgets('quietly prepares the till for offline use, before any screen asks for it', (
      tester,
    ) async {
      final products = FakeProductsApi([]);
      final customers = FakeCustomersApi();

      await pumpAuthenticatedApp(tester, products: products, customers: customers, settle: false);
      await tester.pump(); // let the start-up session restore finish…
      await tester.pumpAndSettle();

      // …the catalogue and the customers were read once, on the app's own initiative, even though
      // nobody has opened the Caisse or the customer list yet (the app is on the dashboard).
      expect(products.listCalls, greaterThanOrEqualTo(1));
      expect(customers.listCalls, greaterThanOrEqualTo(1));
    });
  });

  group('signing out', () {
    testWidgets('forgets the offline cache, so the next account never sees this one\'s data', (
      tester,
    ) async {
      final store =
          MemoryLocalStore()
            ..values['offline_cache:index'] = '["user-1:biz-1|GET /products?"]'
            ..values['offline_cache:entry:user-1:biz-1|GET /products?'] =
                '{"t":"2026-09-19T10:00:00Z","d":{}}';

      await pumpAuthenticatedApp(tester, localStore: store);
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Déconnexion'));
      await tester.pumpAndSettle();

      expect(find.text('Commencer'), findsOneWidget);
      expect(store.values.keys.where((k) => k.startsWith('offline_cache:')), isEmpty);
    });
  });
}
