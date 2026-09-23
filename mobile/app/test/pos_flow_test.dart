import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/api/request_id.dart';
import 'package:thy_app/core/theme/formatters.dart';
import 'package:thy_app/features/business/data/business_api.dart';
import 'package:thy_app/features/customers/data/customer_models.dart';
import 'package:thy_app/features/pos/application/cart.dart';
import 'package:thy_app/features/products/data/product_models.dart';
import 'package:thy_app/features/sales/application/receipt_text.dart';
import 'package:thy_app/features/sales/data/sale_models.dart';

import 'fakes.dart';

const _mamadou = Customer(
  id: 'cust-mamadou',
  fullName: 'Mamadou Diallo',
  phone: '+224655555555',
  currentBalance: 0,
);

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> checkoutFromCart(WidgetTester tester) async {
  await tester.tap(find.text('Voir le panier'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('ENCAISSER'));
  await tester.pumpAndSettle();
}

VoidCallback? confirmCallback(WidgetTester tester) {
  return tester
      .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirmer le paiement'))
      .onPressed;
}

void main() {
  late List<Product> catalog;
  late FakeProductsApi productsApi;
  late FakeSalesApi salesApi;
  late FakeCustomersApi customersApi;

  setUp(() {
    catalog = [
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
    ];
    productsApi = FakeProductsApi(catalog);
    salesApi = FakeSalesApi(catalog: catalog, customers: [_mamadou]);
    customersApi = FakeCustomersApi([_mamadou]);
  });

  Future<void> pumpPos(WidgetTester tester, {List<String>? sharedTexts}) async {
    await pumpAuthenticatedApp(
      tester,
      products: productsApi,
      sales: salesApi,
      customers: customersApi,
      sharedTexts: sharedTexts,
    );
    await openTab(tester, 'Caisse');
  }

  group('cart rules', () {
    late ProviderContainer container;
    late CartNotifier cart;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      cart = container.read(cartProvider.notifier);
    });

    test('adds units, totals them and applies a discount', () {
      cart.add(catalog[0]);
      cart.add(catalog[0]);
      cart.add(catalog[1]);
      cart.setDiscount(1500);

      final state = container.read(cartProvider);
      expect(state.lines, hasLength(2));
      expect(state.unitCount, 3);
      expect(state.subtotal, 18500);
      expect(state.total, 17000);
    });

    test('refuses to go beyond the stock on hand and leaves the cart unchanged', () {
      expect(cart.add(catalog[1]), CartChange.applied);
      expect(cart.add(catalog[1]), CartChange.applied);
      expect(cart.add(catalog[1]), CartChange.insufficientStock);
      expect(container.read(cartProvider).quantityOf('p2'), 2);
    });

    test('a quantity of zero removes the line', () {
      cart.add(catalog[0]);
      cart.setQuantity(catalog[0], 0);
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('flags a discount larger than the subtotal', () {
      cart.add(catalog[0]);
      cart.setDiscount(6000);
      expect(container.read(cartProvider).discountTooHigh, isTrue);
    });

    test('supports fractional quantities', () {
      final rice = testProduct(id: 'rice', name: 'Riz au kilo', stock: 25, salePrice: 9000);
      cart.setQuantity(rice, 2.5);
      expect(container.read(cartProvider).subtotal, 22500);
    });
  });

  group('models and helpers', () {
    test('the checkout payload omits empty payments and zero discount', () {
      const request = CheckoutRequest(
        items: [CheckoutLine(productId: 'p1', quantity: 2)],
        clientRequestId: 'req-12345678',
      );
      expect(request.toJson(), {
        'items': [
          {'productId': 'p1', 'quantity': 2.0},
        ],
        'clientRequestId': 'req-12345678',
      });
    });

    test('a sale parses from the detail shape and from the list shape', () {
      final detail = Sale.fromJson({
        'id': 's1',
        'saleNumber': 'VTE-0001',
        'subtotal': '10000',
        'discountTotal': '0',
        'total': '10000',
        'amountPaid': '4000',
        'amountDue': '6000',
        'status': 'completed',
        'soldAt': '2026-09-19T10:30:00.000Z',
        'customer': {'id': 'c1', 'fullName': 'Mamadou Diallo', 'phone': null},
        'items': [
          {
            'productNameSnapshot': 'Eau',
            'unitPrice': '5000',
            'quantity': '2',
            'lineTotal': '10000',
          },
        ],
        'payments': [
          {'method': 'cash', 'amount': '4000'},
        ],
      });
      expect(detail.isOnCredit, isTrue);
      expect(detail.customer!.fullName, 'Mamadou Diallo');
      expect(detail.items.single.quantity, 2);
      expect(detail.itemCount, 1);

      final listRow = Sale.fromJson({
        'id': 's2',
        'saleNumber': 'VTE-0002',
        'subtotal': '5000',
        'discountTotal': '0',
        'total': '5000',
        'amountPaid': '5000',
        'amountDue': '0',
        'status': 'void',
        'soldAt': '2026-09-19T11:00:00.000Z',
        '_count': {'items': 3},
      });
      expect(listRow.isVoid, isTrue);
      expect(listRow.itemCount, 3);
      expect(listRow.items, isEmpty);
    });

    test('request ids are v4 UUIDs and do not repeat', () {
      final ids = {for (var i = 0; i < 50; i++) generateRequestId()};
      expect(ids, hasLength(50));
      expect(
        ids.first,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });

    test('the receipt text carries business, lines, totals and what is still owed', () {
      final sale = Sale.fromJson({
        'id': 's1',
        'saleNumber': 'VTE-0007',
        'subtotal': '15000',
        'discountTotal': '1000',
        'total': '14000',
        'amountPaid': '4000',
        'amountDue': '10000',
        'status': 'completed',
        'soldAt': '2026-09-19T10:30:00.000Z',
        'customer': {'id': 'c1', 'fullName': 'Mamadou Diallo'},
        'items': [
          {
            'productNameSnapshot': 'Riz local',
            'unitPrice': '5000',
            'quantity': '3',
            'lineTotal': '15000',
          },
        ],
        'payments': [
          {'method': 'cash', 'amount': '4000'},
        ],
      });
      const business = BusinessDetails(
        id: 'b1',
        name: 'Boutique Demo',
        currency: 'GNF',
        address: 'Kaloum, Conakry',
      );

      final text = buildReceiptText(sale, business);

      expect(text, contains('Boutique Demo'));
      expect(text, contains('Kaloum, Conakry'));
      expect(text, contains('Reçu VTE-0007'));
      expect(text, contains('Client : Mamadou Diallo'));
      expect(text, contains('Riz local'));
      expect(text, contains('TOTAL : ${formatMoney(14000)}'));
      expect(text, contains('Espèces : ${formatMoney(4000)}'));
      expect(text, contains('Reste à payer : ${formatMoney(10000)}'));
    });
  });

  group('Caisse', () {
    testWidgets('a cash sale with a discount and change, from cart to receipt', (tester) async {
      await pumpPos(tester);

      await tester.tap(find.text('Eau minérale 1.5L'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eau minérale 1.5L'));
      await tester.pumpAndSettle();
      expect(find.text('2 articles'), findsOneWidget);
      expect(find.text(formatMoney(10000)), findsOneWidget);

      await tester.tap(find.text('Voir le panier'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1000');
      await tester.pumpAndSettle();
      expect(find.text(formatMoney(9000)), findsOneWidget);

      await tester.tap(find.text('ENCAISSER'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10000');
      await tester.pumpAndSettle();
      expect(find.text('Monnaie à rendre : ${formatMoney(1000)}'), findsOneWidget);

      await tester.tap(find.text('Confirmer le paiement'));
      await tester.pumpAndSettle();

      final request = salesApi.requests.single;
      expect(request.items.single.productId, 'p1');
      expect(request.items.single.quantity, 2);
      expect(request.discountTotal, 1000);
      expect(request.customerId, isNull);
      // The payment row records what was applied to the sale, not the cash handed over.
      expect(request.payments.single.method, PaymentMethod.cash);
      expect(request.payments.single.amount, 9000);
      expect(request.clientRequestId, isNotEmpty);

      expect(find.text('VTE-0001'), findsOneWidget);
      expect(find.text('Boutique Demo'), findsOneWidget);
      expect(find.text(formatMoney(1000)), findsWidgets);
      expect(find.text('Monnaie rendue'), findsOneWidget);

      await tester.tap(find.text('Nouvelle vente'));
      await tester.pumpAndSettle();
      expect(find.text('Voir le panier'), findsNothing);
    });

    testWidgets('stock caps the cart and sold-out products cannot be added', (tester) async {
      await pumpPos(tester);

      expect(find.textContaining('Rupture'), findsOneWidget);
      await tester.tap(find.text('Produit épuisé'));
      await tester.pumpAndSettle();
      expect(find.text('Voir le panier'), findsNothing);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Sucre en poudre 1kg'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Stock insuffisant'), findsOneWidget);
      expect(find.text('2 articles'), findsOneWidget);
    });

    testWidgets('a credit sale needs a customer, then records no payment', (tester) async {
      await pumpPos(tester);
      await tester.tap(find.text('Eau minérale 1.5L'));
      await tester.pumpAndSettle();
      await checkoutFromCart(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Crédit'));
      await tester.pumpAndSettle();
      expect(find.text('Sélectionnez un client pour vendre à crédit.'), findsOneWidget);
      expect(confirmCallback(tester), isNull);

      await tester.tap(find.text('Choisir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mamadou Diallo'));
      await tester.pumpAndSettle();
      expect(confirmCallback(tester), isNotNull);

      await tester.tap(find.text('Confirmer le paiement'));
      await tester.pumpAndSettle();

      final request = salesApi.requests.single;
      expect(request.payments, isEmpty);
      expect(request.customerId, _mamadou.id);

      expect(find.text('Mamadou Diallo'), findsOneWidget);
      expect(find.text('Reste à payer'), findsOneWidget);
    });

    testWidgets('a customer can be created on the spot from the picker', (tester) async {
      await pumpPos(tester);
      await tester.tap(find.text('Eau minérale 1.5L'));
      await tester.pumpAndSettle();
      await checkoutFromCart(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Crédit'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choisir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouveau'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Fatoumata Bah');
      await tester.tap(find.text('Créer'));
      await tester.pumpAndSettle();

      expect(customersApi.customers.map((c) => c.fullName), contains('Fatoumata Bah'));
      expect(find.text('Fatoumata Bah'), findsOneWidget);
      expect(confirmCallback(tester), isNotNull);
    });

    testWidgets('retrying after a failed attempt reuses the same request id', (tester) async {
      salesApi.failNextCheckouts = 1;
      await pumpPos(tester);
      await tester.tap(find.text('Eau minérale 1.5L'));
      await tester.pumpAndSettle();
      await checkoutFromCart(tester);

      await tester.tap(find.text('Confirmer le paiement'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Connexion perdue'), findsOneWidget);
      expect(find.text('Confirmer le paiement'), findsOneWidget);

      await tester.tap(find.text('Confirmer le paiement'));
      await tester.pumpAndSettle();

      expect(salesApi.requests, hasLength(2));
      expect(salesApi.requests[0].clientRequestId, salesApi.requests[1].clientRequestId);
      expect(find.text('VTE-0001'), findsOneWidget);
    });

    testWidgets('a non-cash method cannot be over-paid', (tester) async {
      await pumpPos(tester);
      await tester.tap(find.text('Eau minérale 1.5L'));
      await tester.pumpAndSettle();
      await checkoutFromCart(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Carte'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '9000');
      await tester.pumpAndSettle();

      expect(find.text('Le montant dépasse le total à payer.'), findsOneWidget);
      expect(confirmCallback(tester), isNull);
    });
  });

  group('Caisse — barcode reader (keyboard scanner: code + Enter)', () {
    Future<void> scan(WidgetTester tester, String code) async {
      await tester.enterText(find.byType(TextField), code);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    String searchText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('a scanned barcode goes straight into the cart and the field is ready again', (
      tester,
    ) async {
      await pumpPos(tester);

      await scan(tester, '6001234000011');
      expect(find.text('Eau minérale 1.5L ajouté au panier'), findsOneWidget);
      expect(find.text('1 article'), findsOneWidget);
      expect(searchText(tester), isEmpty);
      // The whole catalogue is listed again, not just the scanned product.
      expect(find.text('Sucre en poudre 1kg'), findsOneWidget);

      await scan(tester, '6001234000011');
      expect(find.text('2 articles'), findsOneWidget);
    });

    testWidgets('a SKU works too, ignoring the case', (tester) async {
      await pumpPos(tester);

      await scan(tester, 'suc-1kg');
      expect(find.text('Sucre en poudre 1kg ajouté au panier'), findsOneWidget);
      expect(find.text('1 article'), findsOneWidget);
    });

    testWidgets('a partial code never adds anything — it only filters the list', (tester) async {
      await pumpPos(tester);

      await scan(tester, '600123400');
      expect(find.text('Voir le panier'), findsNothing);
      expect(find.text('Eau minérale 1.5L'), findsOneWidget);
      expect(find.text('Produit épuisé'), findsOneWidget);
      expect(find.text('Sucre en poudre 1kg'), findsNothing);
    });

    testWidgets('an unknown barcode says so and adds nothing', (tester) async {
      await pumpPos(tester);

      await scan(tester, '9999999999999');
      expect(find.text('Aucun produit avec le code-barres 9999999999999'), findsOneWidget);
      // The list explains itself instead of claiming the shop has no products at all.
      expect(find.text('Aucun produit ne correspond à « 9999999999999 ».'), findsOneWidget);
      expect(find.textContaining('Ajoutez des produits'), findsNothing);
      expect(find.text('Voir le panier'), findsNothing);
    });

    testWidgets('a sold-out product is refused with the stock message', (tester) async {
      await pumpPos(tester);

      await scan(tester, '6001234000035');
      expect(find.textContaining('Stock insuffisant pour Produit épuisé'), findsOneWidget);
      expect(find.text('Voir le panier'), findsNothing);
    });

    testWidgets('a normal name search on Enter just filters', (tester) async {
      await pumpPos(tester);

      await scan(tester, 'sucre');
      expect(find.text('Voir le panier'), findsNothing);
      expect(find.text('Sucre en poudre 1kg'), findsOneWidget);
      expect(find.text('Eau minérale 1.5L'), findsNothing);
    });

    test('matchesCode is exact on barcode or SKU, blank never matches', () {
      final product = testProduct(id: 'x', name: 'X', barcode: '123456789', sku: 'AbC-1');
      expect(product.matchesCode('123456789'), isTrue);
      expect(product.matchesCode(' 123456789 '), isTrue);
      expect(product.matchesCode('abc-1'), isTrue);
      expect(product.matchesCode('12345678'), isFalse);
      expect(product.matchesCode(''), isFalse);
      expect(testProduct(id: 'y', name: 'Y').matchesCode('anything'), isFalse);
    });
  });

  group('sales history', () {
    Future<void> seedSale() async {
      await salesApi.checkout(
        const CheckoutRequest(
          items: [CheckoutLine(productId: 'p1', quantity: 1)],
          payments: [CheckoutPayment(method: PaymentMethod.cash, amount: 5000)],
          clientRequestId: 'seed-request-0001',
        ),
      );
    }

    Future<void> openSeededReceipt(WidgetTester tester, {List<String>? sharedTexts}) async {
      await pumpPos(tester, sharedTexts: sharedTexts);
      await openTab(tester, 'Plus');
      await tester.tap(find.text('Historique des ventes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VTE-0001'));
      await tester.pumpAndSettle();
    }

    testWidgets('a receipt can be shared as text', (tester) async {
      await seedSale();
      final shared = <String>[];
      await openSeededReceipt(tester, sharedTexts: shared);

      await tester.tap(find.text('Partager'));
      await tester.pumpAndSettle();

      expect(shared, hasLength(1));
      expect(shared.single, contains('Boutique Demo'));
      expect(shared.single, contains('VTE-0001'));
      expect(shared.single, contains('TOTAL : ${formatMoney(5000)}'));
    });

    testWidgets('a sale can be voided from its receipt', (tester) async {
      await seedSale();
      await openSeededReceipt(tester);
      expect(find.text('VENTE ANNULÉE'), findsNothing);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler la vente'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Annuler la vente'));
      await tester.pumpAndSettle();

      expect(salesApi.voided, ['sale-1']);
      expect(find.text('VENTE ANNULÉE'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });
  });
}
