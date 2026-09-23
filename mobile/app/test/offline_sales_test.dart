import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/offline/offline_providers.dart';
import 'package:thy_app/core/storage/local_store.dart';
import 'package:thy_app/core/theme/formatters.dart';
import 'package:thy_app/features/customers/data/customer_models.dart';
import 'package:thy_app/features/products/application/products_providers.dart';
import 'package:thy_app/features/products/data/product_models.dart';
import 'package:thy_app/features/sales/data/sale_models.dart';
import 'package:thy_app/features/sales/offline/pending_sale.dart';
import 'package:thy_app/features/sales/offline/pending_sales_repository.dart';
import 'package:thy_app/features/sales/offline/sales_sync_service.dart';

import 'fakes.dart';

const _pendingKey = 'pending_sales:v1:user-1';

void main() {
  late List<Product> catalog;
  late FakeProductsApi productsApi;
  late FakeSalesApi salesApi;
  late MemoryLocalStore store;

  setUp(() {
    catalog = [
      testProduct(id: 'p1', name: 'Eau minérale 1.5L', stock: 10, salePrice: 5000),
      testProduct(id: 'p2', name: 'Sucre en poudre 1kg', stock: 5, salePrice: 8500),
    ];
    productsApi = FakeProductsApi(catalog);
    salesApi = FakeSalesApi(catalog: catalog);
    store = MemoryLocalStore();
  });

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, {Duration? syncInterval}) async {
    await pumpAuthenticatedApp(
      tester,
      products: productsApi,
      sales: salesApi,
      localStore: store,
      syncInterval: syncInterval,
    );
    await openTab(tester, 'Caisse');
  }

  /// Rings up [product] × [times] in cash, from the Caisse tab to the "Confirmer" tap.
  Future<void> sell(WidgetTester tester, String product, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text(product));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Voir le panier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ENCAISSER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer le paiement'));
    await tester.pumpAndSettle();
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  List<dynamic> storedQueue() {
    final raw = store.values[_pendingKey];
    return raw == null ? [] : jsonDecode(raw) as List<dynamic>;
  }

  Future<void> syncNow(WidgetTester tester) async {
    await container(tester).read(salesSyncServiceProvider).syncNow();
    await tester.pumpAndSettle();
  }

  group('ringing up a sale with no network', () {
    testWidgets('keeps the sale on the phone and hands over a receipt', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);

      await sell(tester, 'Eau minérale 1.5L', times: 2);

      expect(find.text('Vente enregistrée sur ce téléphone'), findsOneWidget);
      expect(find.textContaining('HL-'), findsWidgets, reason: 'a provisional number');
      expect(find.text(formatMoney(10000)), findsWidgets);
      expect(find.text('Nouvelle vente'), findsOneWidget);

      // Nothing was lost: the sale is stored, with the same id the server will recognise.
      expect(salesApi.recordedCount, 0);
      final queue = storedQueue();
      expect(queue, hasLength(1));
      expect(queue.single['id'], salesApi.requests.single.clientRequestId);
      expect(queue.single['status'], 'waiting');
    });

    testWidgets('the stock shown already counts the sale, so the last unit is not sold twice', (
      tester,
    ) async {
      salesApi.networkDown = true;
      await pump(tester);

      await sell(tester, 'Eau minérale 1.5L', times: 2);
      await tester.tap(find.text('Nouvelle vente'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Stock : 8'), findsOneWidget, reason: '10 in stock, 2 just sold');
      await openTab(tester, 'Stock');
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('a banner says so, and opens the list of waiting sales', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L');
      await tester.tap(find.text('Nouvelle vente'));
      await tester.pumpAndSettle();

      expect(find.text('1 vente à envoyer.'), findsOneWidget);

      container(tester).read(connectionStatusProvider.notifier).report(false);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hors ligne · 1 vente enregistrée sur ce téléphone'),
        findsOneWidget,
      );

      await tester.tap(find.textContaining('Hors ligne'));
      await tester.pumpAndSettle();
      expect(find.text('Ventes en attente'), findsOneWidget);
      expect(find.textContaining('HL-'), findsOneWidget);
      expect(find.text("En attente d'envoi"), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown to the cashier, not queued', (tester) async {
      salesApi.failWithStatus = 500;
      await pump(tester);

      await sell(tester, 'Eau minérale 1.5L');

      expect(find.text('Erreur du serveur'), findsOneWidget);
      expect(
        find.text('Confirmer le paiement'),
        findsOneWidget,
        reason: 'still on the payment screen',
      );
      expect(storedQueue(), isEmpty);
    });

    testWidgets('a credit sale is kept with its customer and what is still owed', (tester) async {
      final customers = FakeCustomersApi([
        const Customer(
          id: 'cust-1',
          fullName: 'Mamadou Diallo',
          phone: '+224655555555',
          currentBalance: 0,
        ),
      ]);
      salesApi.networkDown = true;
      await pumpAuthenticatedApp(
        tester,
        products: productsApi,
        sales: salesApi,
        customers: customers,
        localStore: store,
      );
      await openTab(tester, 'Caisse');
      await tester.tap(find.text('Eau minérale 1.5L'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voir le panier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ENCAISSER'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Crédit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mamadou Diallo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer le paiement'));
      await tester.pumpAndSettle();

      expect(find.text('Vente enregistrée sur ce téléphone'), findsOneWidget);
      expect(find.text('Mamadou Diallo'), findsOneWidget);
      expect(find.text('Reste à payer'), findsOneWidget);
      expect(storedQueue().single['request']['customerId'], 'cust-1');
    });
  });

  group('sending the waiting sales', () {
    Future<void> queueOneSale(WidgetTester tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L', times: 2);
    }

    testWidgets(
      'once the server is back: sent with its real date, and the receipt turns into the real one',
      (tester) async {
        await queueOneSale(tester);
        final firstAttempt = salesApi.requests.single;

        salesApi.networkDown = false;
        await syncNow(tester);

        // The same sale (same id), flagged as already happened, dated when it really happened.
        final sent = salesApi.requests.last;
        expect(sent.clientRequestId, firstAttempt.clientRequestId);
        expect(sent.offline, isTrue);
        expect(sent.soldAt, isNotNull);
        expect(salesApi.recordedCount, 1);

        expect(
          find.text('VTE-0001'),
          findsOneWidget,
          reason: 'the open receipt moved on to the real sale',
        );
        expect(find.text('Vente enregistrée sur ce téléphone'), findsNothing);
        expect(storedQueue(), isEmpty);
      },
    );

    testWidgets('a sale the server already recorded (its answer was lost) is never sold twice', (
      tester,
    ) async {
      salesApi.loseNextResponse = true; // recorded server-side, but the app never hears back
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L');
      expect(salesApi.recordedCount, 1);
      expect(storedQueue(), hasLength(1), reason: 'the app cannot know, so it keeps the sale');

      await syncNow(tester);

      expect(salesApi.recordedCount, 1, reason: 'the replay was recognised');
      expect(storedQueue(), isEmpty);
    });

    testWidgets('a server that is temporarily unwell keeps the sale waiting', (tester) async {
      await queueOneSale(tester);
      salesApi.networkDown = false;
      salesApi.failWithStatus = 503;

      await syncNow(tester);

      expect(find.text('Vente enregistrée sur ce téléphone'), findsOneWidget);
      expect(storedQueue().single['status'], 'waiting');
      expect(storedQueue().single['attempts'], 1);

      salesApi.failWithStatus = null;
      await syncNow(tester);
      expect(salesApi.recordedCount, 1);
    });

    testWidgets(
      'a sale the server refuses for good is kept, with the reason, until the user decides',
      (tester) async {
        await queueOneSale(tester);
        salesApi.networkDown = false;
        salesApi.rejectWith = 'Client introuvable.';

        await syncNow(tester);

        expect(find.text('Le serveur a refusé cette vente'), findsOneWidget);
        expect(find.text('Client introuvable.'), findsOneWidget);
        expect(storedQueue().single['status'], 'failed');
        expect(salesApi.recordedCount, 0);

        // The cause is fixed: one tap and it goes.
        salesApi.rejectWith = null;
        await tester.tap(find.text('Réessayer'));
        await tester.pumpAndSettle();
        expect(salesApi.recordedCount, 1);
        expect(find.text('VTE-0001'), findsOneWidget);
      },
    );

    testWidgets('one refused sale does not block the ones behind it', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L');
      await tester.tap(find.text('Nouvelle vente'));
      await tester.pumpAndSettle();
      await sell(tester, 'Sucre en poudre 1kg');
      final firstId = salesApi.requests.first.clientRequestId;

      salesApi.networkDown = false;
      salesApi.rejectWith = 'Produit inactif';
      salesApi.rejectOnlyRequests = {firstId};
      await syncNow(tester);

      expect(salesApi.recordedCount, 1, reason: 'the second sale went through');
      final left = container(tester).read(pendingSalesProvider);
      expect(left, hasLength(1));
      expect(left.single.id, firstId);
      expect(left.single.isFailed, isTrue);
    });

    testWidgets('sales go out oldest first', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L');
      await tester.tap(find.text('Nouvelle vente'));
      await tester.pumpAndSettle();
      await sell(tester, 'Sucre en poudre 1kg');
      final ids = salesApi.requests.map((r) => r.clientRequestId).toList();
      salesApi.requests.clear();

      salesApi.networkDown = false;
      await syncNow(tester);

      expect(salesApi.requests.map((r) => r.clientRequestId).toList(), ids);
    });
  });

  group('sending automatically', () {
    testWidgets('as soon as the server answers again', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L');
      final status = container(tester).read(connectionStatusProvider.notifier);
      status.report(false);
      await tester.pumpAndSettle();
      salesApi.networkDown = false;

      status.report(true); // some request got through
      await tester.pumpAndSettle();

      expect(salesApi.recordedCount, 1);
      expect(storedQueue(), isEmpty);
    });

    testWidgets('on a timer while something waits', (tester) async {
      salesApi.networkDown = true;
      await pump(tester, syncInterval: const Duration(seconds: 30));
      await sell(tester, 'Eau minérale 1.5L');
      salesApi.networkDown = false;
      expect(salesApi.recordedCount, 0);

      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();

      expect(salesApi.recordedCount, 1);
      await tester.pumpWidget(const SizedBox()); // stop the timer before the test ends
    });
  });

  group('waiting sales survive', () {
    testWidgets('closing and reopening the app', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L');
      await tester.pumpWidget(const SizedBox()); // the app is closed

      await pump(tester); // …and opened again, same phone storage
      expect(find.text('1 vente à envoyer.'), findsOneWidget);

      salesApi.networkDown = false;
      await syncNow(tester);
      expect(salesApi.recordedCount, 1);
    });

    testWidgets('signing out — after a warning', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L');
      await tester.tap(find.text('Nouvelle vente'));
      await tester.pumpAndSettle();

      await openTab(tester, 'Plus');
      await tester.tap(find.text('Déconnexion'));
      await tester.pumpAndSettle();
      expect(find.text('Des ventes ne sont pas envoyées'), findsOneWidget);

      await tester.tap(find.text('Rester connecté'));
      await tester.pumpAndSettle();
      expect(find.text('Déconnexion'), findsOneWidget, reason: 'still signed in');

      await tester.tap(find.text('Déconnexion'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();

      expect(find.text('Commencer'), findsOneWidget);
      expect(storedQueue(), hasLength(1), reason: 'kept for the next sign-in');
    });
  });

  group('deleting a waiting sale', () {
    testWidgets('is confirmed, then gives the stock back', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L', times: 2);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer cette vente'));
      await tester.pumpAndSettle();
      expect(find.textContaining("n'a pas encore été enregistrée"), findsOneWidget);

      await tester.tap(find.text('Garder la vente'));
      await tester.pumpAndSettle();
      expect(storedQueue(), hasLength(1));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer cette vente'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(find.text('Toutes les ventes sont envoyées au serveur.'), findsOneWidget);
      expect(storedQueue(), isEmpty);
      // The 2 units are back on the shelf as far as the app is concerned.
      expect(container(tester).read(pendingStockProvider).of('p1'), 0);
    });
  });

  group('the sales history', () {
    testWidgets('points at the sales that are not in the list yet', (tester) async {
      salesApi.networkDown = true;
      await pump(tester);
      await sell(tester, 'Eau minérale 1.5L');
      await tester.tap(find.text('Nouvelle vente'));
      await tester.pumpAndSettle();

      await openTab(tester, 'Plus');
      await tester.tap(find.text('Historique des ventes'));
      await tester.pumpAndSettle();

      expect(find.text('1 vente en attente d\'envoi'), findsOneWidget);
      await tester.tap(find.text('1 vente en attente d\'envoi'));
      await tester.pumpAndSettle();
      expect(find.text('Ventes en attente'), findsOneWidget);
    });
  });

  group('models', () {
    test('a waiting sale survives being written to the phone and read back', () {
      final receipt = provisionalReceipt(
        requestId: '3f9a21c4-aaaa-4bbb-8ccc-000000000001',
        at: DateTime.utc(2026, 9, 19, 10, 30),
        subtotal: 10000,
        discountTotal: 1000,
        total: 9000,
        amountPaid: 4000,
        items: const [SaleItem(productName: 'Eau', unitPrice: 5000, quantity: 2, lineTotal: 10000)],
        payments: const [SalePayment(method: 'cash', amount: 4000)],
        customer: const SaleCustomer(id: 'c1', fullName: 'Mamadou Diallo', phone: '+224655555555'),
      );
      final sale = PendingSale(
        id: receipt.id,
        businessId: 'biz-1',
        createdAt: DateTime.utc(2026, 9, 19, 10, 30),
        request: CheckoutRequest(
          items: const [CheckoutLine(productId: 'p1', quantity: 2)],
          payments: const [CheckoutPayment(method: 'cash', amount: 4000)],
          discountTotal: 1000,
          customerId: 'c1',
          clientRequestId: receipt.id,
        ),
        receipt: receipt,
        status: PendingSaleStatus.failed,
        attempts: 3,
        lastError: 'Client introuvable.',
      );

      final back = PendingSale.fromJson(
        jsonDecode(jsonEncode(sale.toJson())) as Map<String, dynamic>,
      );

      expect(back.id, sale.id);
      expect(back.createdAt, sale.createdAt);
      expect(back.isFailed, isTrue);
      expect(back.attempts, 3);
      expect(back.lastError, 'Client introuvable.');
      expect(back.request.toJson(), sale.request.toJson());
      expect(back.receipt.total, 9000);
      expect(back.receipt.amountDue, 5000);
      expect(back.receipt.customer!.fullName, 'Mamadou Diallo');
      expect(back.receipt.items.single.productName, 'Eau');
    });

    test('what is sent to the server carries the real date and the offline flag', () {
      const request = CheckoutRequest(
        items: [CheckoutLine(productId: 'p1', quantity: 1)],
        clientRequestId: 'req-12345678',
      );

      final json = request.asOffline(DateTime.utc(2026, 9, 19, 8)).toJson();

      expect(json['offline'], true);
      expect(json['soldAt'], '2026-09-19T08:00:00.000Z');
      expect(json['clientRequestId'], 'req-12345678');
      // An ordinary online sale sends neither.
      expect(request.toJson().containsKey('offline'), isFalse);
      expect(request.toJson().containsKey('soldAt'), isFalse);
    });

    test('the provisional number is short and readable', () {
      expect(provisionalSaleNumber('3f9a21c4-aaaa-4bbb-8ccc-000000000001'), 'HL-3F9A21');
      expect(provisionalSaleNumber('ab'), 'HL-AB');
    });

    test('pending stock compares by value, so screens only refresh when a quantity changes', () {
      expect(const PendingStock({'p1': 2}) == const PendingStock({'p1': 2}), isTrue);
      expect(const PendingStock({'p1': 2}) == const PendingStock({'p1': 3}), isFalse);
      expect(const PendingStock({}).of('p9'), 0);
    });

    test('a product net of waiting sales', () {
      final product = testProduct(id: 'p1', name: 'Eau', stock: 10);
      final net = netOfPendingSales([product], const PendingStock({'p1': 4}));
      expect(net.single.currentStock, 6);
      expect(net.single.name, 'Eau');
      expect(netOfPendingSales([product], const PendingStock({})).single.currentStock, 10);
    });
  });
}
