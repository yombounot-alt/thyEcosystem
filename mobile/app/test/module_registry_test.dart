import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_app/core/modules/app_module.dart';
import 'package:thy_app/core/modules/module_registry.dart';
import 'package:thy_app/modules/business/business_module.dart';

import 'fakes.dart';

/// A second module, as Marketplace will be: one tab, one inner route, one "Plus" entry, a badge.
class _FakeMarketModule extends AppModule {
  const _FakeMarketModule();

  @override
  String get id => 'market';

  @override
  ModuleTab get home => ModuleTab(
    path: '/market-home',
    label: 'Accueil',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    screen: () => const Scaffold(body: Text('Accueil marché')),
  );

  @override
  List<ModuleTab> get tabs => [
    ModuleTab(
      path: '/market',
      label: 'Marché',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront,
      screen: () => const Scaffold(body: Center(child: Text('Annonces du marché'))),
    ),
  ];

  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: '/market/orders',
      builder:
          (context, state) => Scaffold(
            appBar: AppBar(title: const Text('Commandes')),
            body: const Text('Mes commandes'),
          ),
    ),
  ];

  @override
  Widget moreSection() => Builder(
    builder:
        (context) => ListTile(
          title: const Text('Mes commandes'),
          onTap: () => context.push('/market/orders'),
        ),
  );

  @override
  int moreBadge(WidgetRef ref) => 2;
}

void main() {
  group('navigation policy', () {
    test('Business alone keeps the four tabs merchants know', () {
      final nav = buildNavigation(const [BusinessModule()]);
      expect(nav.tabs.map((t) => t.path), ['/dashboard', '/pos', '/stock', '/more']);
      expect(nav.tabs.map((t) => t.label), ['Accueil', 'Caisse', 'Stock', 'Plus']);
    });

    test('the main module gives "Accueil"; other modules add their tabs before "Plus"', () {
      final nav = buildNavigation(const [BusinessModule(), _FakeMarketModule()]);
      expect(nav.tabs.map((t) => t.path), ['/dashboard', '/pos', '/stock', '/market', '/more']);
    });

    test('more module tabs than the 5 slots allow is refused (the policy must choose)', () {
      expect(
        () => buildNavigation(const [BusinessModule(), _FakeMarketModule(), _FakeMarketModule()]),
        throwsStateError,
      );
    });
  });

  testWidgets(
    'a new module shows up in the tabs, the routes and "Plus" without touching the shell',
    (tester) async {
      await pumpAuthenticatedApp(
        tester,
        extraOverrides: [
          appModulesProvider.overrideWithValue(const [BusinessModule(), _FakeMarketModule()]),
        ],
      );

      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Marché')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Annonces du marché'), findsOneWidget);

      // Its badge adds up on "Plus", and its entry leads to its own route.
      expect(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('2')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mes commandes'));
      await tester.tap(find.text('Mes commandes'));
      await tester.pumpAndSettle();
      expect(find.text('Mes commandes'), findsOneWidget);

      // Business entries are still there.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Clients'), findsOneWidget);
    },
  );
}
