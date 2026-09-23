import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/scanning/scan_types.dart';

import 'fakes.dart';

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  late FakeProductsApi productsApi;

  setUp(() {
    productsApi = FakeProductsApi([
      testProduct(
        id: 'p1',
        name: 'Eau minérale 1.5L',
        stock: 10,
        salePrice: 5000,
        barcode: '6001234000011',
      ),
      testProduct(id: 'p2', name: 'Sucre en poudre 1kg', stock: 2, salePrice: 8500, sku: 'SUC-1KG'),
      testProduct(
        id: 'p3',
        name: 'Produit épuisé',
        stock: 0,
        salePrice: 1000,
        barcode: '6001234000035',
      ),
    ]);
  });

  group('Caisse: scanning a basket with the camera', () {
    testWidgets('every code read goes into the cart, and the scanner says what happened', (
      tester,
    ) async {
      final scanner = FakeBarcodeScanner([
        '6001234000011',
        '6001234000011', // a second identical article
        '9999999999999', // not in the catalogue
        '6001234000035', // sold out
        'SUC-1KG', // a SKU works as well as a barcode
      ]);
      await pumpAuthenticatedApp(tester, products: productsApi, barcodeScanner: scanner);
      await openTab(tester, 'Caisse');

      await tester.tap(find.byTooltip('Scanner avec la caméra'));
      await tester.pumpAndSettle();

      expect(scanner.opened, 1);
      expect(scanner.lastContinuous, isTrue, reason: 'stays open for the next article');
      expect(scanner.feedback.map((f) => f.message).toList(), [
        'Eau minérale 1.5L ajouté · 1 dans le panier',
        'Eau minérale 1.5L ajouté · 2 dans le panier',
        'Aucun produit avec le code 9999999999999',
        'Stock insuffisant pour Produit épuisé (disponible : 0)',
        'Sucre en poudre 1kg ajouté · 1 dans le panier',
      ]);
      expect(scanner.feedback.map((f) => f.isProblem).toList(), [false, false, true, true, false]);

      // Back on the Caisse, the basket is there.
      expect(find.text('3 articles'), findsOneWidget);
    });

    testWidgets('a partial code never adds a product that merely looks similar', (tester) async {
      final scanner = FakeBarcodeScanner(['600123400']); // a prefix of two barcodes
      await pumpAuthenticatedApp(tester, products: productsApi, barcodeScanner: scanner);
      await openTab(tester, 'Caisse');

      await tester.tap(find.byTooltip('Scanner avec la caméra'));
      await tester.pumpAndSettle();

      expect(scanner.feedback.single.isProblem, isTrue);
      expect(find.text('Voir le panier'), findsNothing);
    });

    testWidgets('the camera button is not offered where there is no camera scanning (browser)', (
      tester,
    ) async {
      await pumpAuthenticatedApp(tester, products: productsApi, cameraScanning: false);
      await openTab(tester, 'Caisse');

      expect(find.byTooltip('Scanner avec la caméra'), findsNothing);
      expect(find.byIcon(Icons.search), findsOneWidget, reason: 'the search field is still there');
    });
  });

  group('Product form: reading a barcode instead of typing it', () {
    testWidgets('fills the barcode field and saves it with the product', (tester) async {
      final scanner = FakeBarcodeScanner(['6009999000111', '6009999000222']);
      await pumpAuthenticatedApp(tester, products: productsApi, barcodeScanner: scanner);
      await openTab(tester, 'Stock');
      await tester.tap(find.text('Produit'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Scanner le code-barres'));
      await tester.pumpAndSettle();

      expect(scanner.lastContinuous, isFalse, reason: 'closes after the first code');
      expect(scanner.feedback, hasLength(1));
      expect(find.widgetWithText(TextFormField, '6009999000111'), findsOneWidget);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Lait concentré');
      await tester.enterText(fields.at(2), '3500');
      await tester.ensureVisible(find.text('Ajouter le produit'));
      await tester.tap(find.text('Ajouter le produit'));
      await tester.pumpAndSettle();

      expect(productsApi.created.single.barcode, '6009999000111');
    });
  });

  group('ScanDebouncer', () {
    late DateTime now;
    late ScanDebouncer debouncer;

    setUp(() {
      now = DateTime(2026, 9, 20, 10);
      debouncer = ScanDebouncer(clock: () => now);
    });

    void after(int milliseconds) => now = now.add(Duration(milliseconds: milliseconds));

    test('the first sighting of a code is accepted', () {
      expect(debouncer.accept('A'), isTrue);
    });

    test('a code held in front of the camera is read once, however long it stays', () {
      expect(debouncer.accept('A'), isTrue);
      for (var i = 0; i < 20; i++) {
        after(100); // seen again every 100 ms for 2 seconds
        expect(debouncer.accept('A'), isFalse, reason: 'sighting ${i + 1}');
      }
    });

    test('taking it away and showing it again reads it again (a second identical article)', () {
      expect(debouncer.accept('A'), isTrue);
      after(1500); // out of view for longer than the gap
      expect(debouncer.accept('A'), isTrue);
    });

    test('another code is accepted immediately, even right after the first', () {
      expect(debouncer.accept('A'), isTrue);
      after(50);
      expect(debouncer.accept('B'), isTrue);
    });
  });
}
