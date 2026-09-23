import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/features/inventory/data/inventory_models.dart';
import 'package:thy_app/features/products/data/product_models.dart';

import 'fakes.dart';

Future<void> openStockTab(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Stock')));
  await tester.pumpAndSettle();
}

void main() {
  group('Product model', () {
    test('parses Prisma decimal strings and derives margin and stock status', () {
      final product = Product.fromJson({
        'id': 'p1',
        'name': 'Riz local 25kg',
        'categoryId': 'c1',
        'category': {'id': 'c1', 'name': 'Alimentaire'},
        'unit': 'unite',
        'purchasePrice': '180000',
        'salePrice': '220000',
        'currentStock': '4',
        'lowStockThreshold': '5',
        'isActive': true,
      });

      expect(product.salePrice, 220000);
      expect(product.categoryName, 'Alimentaire');
      expect(product.margin, 40000);
      expect(product.marginPercent, closeTo(18.18, 0.01));
      expect(product.stockValue, 720000);
      expect(product.isLowStock, isTrue);
      expect(product.isOutOfStock, isFalse);
    });

    test('an out-of-stock product is not also reported as low stock', () {
      final product = testProduct(id: 'p', name: 'Vide', stock: 0, lowStockThreshold: 5);
      expect(product.isOutOfStock, isTrue);
      expect(product.isLowStock, isFalse);
    });

    test('create payload omits unset optional fields, update payload clears them', () {
      const input = ProductInput(name: 'Sucre', salePrice: 8500, purchasePrice: 6000);

      expect(input.toCreateJson(), {'name': 'Sucre', 'salePrice': 8500.0, 'purchasePrice': 6000.0});
      expect(input.toUpdateJson()['categoryId'], isNull);
      expect(input.toUpdateJson().containsKey('categoryId'), isTrue);
      expect(input.toUpdateJson().containsKey('initialStock'), isFalse);
    });

    test('movement types map to the right direction', () {
      expect(MovementType.isIncoming(MovementType.purchaseIn), isTrue);
      expect(MovementType.isIncoming(MovementType.saleOut), isFalse);
      expect(MovementType.isIncoming(MovementType.adjustmentOut), isFalse);
    });
  });

  group('Stock tab', () {
    late FakeProductsApi productsApi;

    setUp(() {
      productsApi = FakeProductsApi([
        testProduct(id: 'p1', name: 'Eau minérale 1.5L', stock: 10, lowStockThreshold: 3),
        testProduct(id: 'p2', name: 'Sucre en poudre 1kg', stock: 2, lowStockThreshold: 5),
      ]);
    });

    testWidgets('lists products and narrows down to low stock', (tester) async {
      await pumpAuthenticatedApp(tester, products: productsApi);
      await openStockTab(tester);

      expect(find.text('Eau minérale 1.5L'), findsOneWidget);
      expect(find.text('Sucre en poudre 1kg'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Stock faible'));
      await tester.pumpAndSettle();

      expect(find.text('Eau minérale 1.5L'), findsNothing);
      expect(find.text('Sucre en poudre 1kg'), findsOneWidget);
    });

    testWidgets('creating a product sends what was typed and returns to the list', (tester) async {
      await pumpAuthenticatedApp(tester, products: productsApi);
      await openStockTab(tester);

      await tester.tap(find.text('Produit'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Riz local');
      await tester.enterText(fields.at(2), '220 000');
      await tester.enterText(fields.at(3), '5');
      await tester.tap(find.text('Ajouter le produit'));
      await tester.pumpAndSettle();

      expect(productsApi.created, hasLength(1));
      expect(productsApi.created.single.name, 'Riz local');
      expect(productsApi.created.single.salePrice, 220000);
      expect(productsApi.created.single.initialStock, 5);
      expect(find.text('Riz local'), findsOneWidget);
    });

    testWidgets('the product form refuses a missing name and price', (tester) async {
      await pumpAuthenticatedApp(tester, products: productsApi);
      await openStockTab(tester);

      await tester.tap(find.text('Produit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter le produit'));
      await tester.pumpAndSettle();

      expect(find.text('Nom requis'), findsOneWidget);
      expect(find.text('Prix requis'), findsOneWidget);
      expect(productsApi.created, isEmpty);
    });

    testWidgets('a physical count records the gap as an adjustment', (tester) async {
      final inventory = FakeInventoryApi();
      await pumpAuthenticatedApp(tester, products: productsApi, inventory: inventory);
      await openStockTab(tester);

      await tester.tap(find.text('Eau minérale 1.5L'));
      await tester.pumpAndSettle();
      expect(find.text('Marge'), findsOneWidget);

      await tester.tap(find.text('Ajuster'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inventaire'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '7');
      await tester.pumpAndSettle();
      expect(find.textContaining('écart de −3'), findsOneWidget);

      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(inventory.recorded, hasLength(1));
      expect(inventory.recorded.single.productId, 'p1');
      expect(inventory.recorded.single.type, MovementType.adjustmentOut);
      expect(inventory.recorded.single.quantity, 3);
      expect(inventory.recorded.single.note, contains('Inventaire'));
    });

    testWidgets('a stock-out larger than the available stock is refused locally', (tester) async {
      final inventory = FakeInventoryApi();
      await pumpAuthenticatedApp(tester, products: productsApi, inventory: inventory);
      await openStockTab(tester);

      await tester.tap(find.text('Sucre en poudre 1kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajuster'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sortie'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Stock insuffisant'), findsOneWidget);
      expect(inventory.recorded, isEmpty);
    });
  });
}
