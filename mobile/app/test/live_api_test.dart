// Contract check of the Dart API layer against a REAL running backend (backend/, dev stack).
// Skipped unless a base URL is given. Start the backend with a fixed dev OTP (never in production):
//   DEV_FIXED_OTP=123456 node --env-file=.env dist/main.js        (from backend/)
//   flutter test test/live_api_test.dart --dart-define=THY_API_BASE_URL=http://localhost:3300/api/v1
// Every test provisions its own brand-new account and business, so runs never interfere.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/api/api_client.dart';
import 'package:thy_app/core/api/api_exception.dart';
import 'package:thy_app/core/api/request_id.dart';
import 'package:thy_app/features/auth/data/auth_api.dart';
import 'package:thy_app/features/business/data/business_api.dart';
import 'package:thy_app/features/categories/data/categories_api.dart';
import 'package:thy_app/features/customers/data/customer_models.dart';
import 'package:thy_app/features/customers/data/customers_api.dart';
import 'package:thy_app/features/dashboard/data/dashboard_api.dart';
import 'package:thy_app/features/dashboard/data/dashboard_models.dart';
import 'package:thy_app/features/expenses/data/expense_models.dart';
import 'package:thy_app/features/expenses/data/expenses_api.dart';
import 'package:thy_app/features/inventory/data/inventory_api.dart';
import 'package:thy_app/features/inventory/data/inventory_models.dart';
import 'package:thy_app/features/payments/data/payment_method_models.dart';
import 'package:thy_app/features/payments/data/payment_models.dart';
import 'package:thy_app/features/payments/data/payments_api.dart';
import 'package:thy_app/features/products/data/product_models.dart';
import 'package:thy_app/features/products/data/products_api.dart';
import 'package:thy_app/features/sales/data/sale_models.dart';
import 'package:thy_app/features/sales/data/sales_api.dart';

import 'fakes.dart';

const _liveBaseUrl = String.fromEnvironment('THY_API_BASE_URL');
const _devOtp = String.fromEnvironment('THY_DEV_OTP', defaultValue: '123456');

int _phoneSeq = 0;

/// A client signed in as a brand-new owner of a brand-new shop, stocked like the old demo data:
/// a "Boissons" category, "Eau minérale 1.5L" (5 000 GNF) and a customer "Mamadou Diallo".
Future<ApiClient> _loggedInClient() async {
  final storage = FakeTokenStorage();
  final client = ApiClient(storage);
  final auth = AuthApi(client.dio);

  final digits = '${DateTime.now().microsecondsSinceEpoch}${++_phoneSeq}';
  final phone = '+2246${digits.substring(digits.length - 8)}';
  await auth.requestOtp(phone: phone);
  final tokens = await auth.verifyOtp(phone: phone, code: _devOtp);
  await storage.saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
  await auth.updateFullName('Testeur Live');

  final shop = await BusinessApi(client.dio).create(
    name: 'Boutique live ${DateTime.now().millisecondsSinceEpoch}',
    businessType: 'commerce',
    currency: 'GNF',
  );
  await storage.saveAccessToken(shop.accessToken);

  final drinks = await CategoriesApi(client.dio).create('Boissons');
  await ProductsApi(client.dio).create(
    ProductInput(
      name: 'Eau minérale 1.5L',
      salePrice: 5000,
      purchasePrice: 3000,
      initialStock: 100,
      categoryId: drinks.id,
    ),
  );
  await CustomersApi(client.dio).create(fullName: 'Mamadou Diallo', phone: '+224622000111');
  return client;
}

void main() {
  group(
    'live backend contract',
    skip: _liveBaseUrl.isEmpty ? 'set --dart-define=THY_API_BASE_URL to run' : false,
    () {
      test('products, categories and stock movements round-trip through the real API', () async {
        final client = await _loggedInClient();
        final profile = await AuthApi(client.dio).me();
        expect(profile.activeBusinessId, isNotNull);

        final categories = await CategoriesApi(client.dio).list();
        expect(categories.map((c) => c.name), contains('Boissons'));

        final products = ProductsApi(client.dio);
        final inventory = InventoryApi(client.dio);

        final seeded = await products.list();
        expect(seeded.items.map((p) => p.name), contains('Eau minérale 1.5L'));
        expect(seeded.items.every((p) => p.salePrice > 0), isTrue);

        final name = 'zz-live-test-${DateTime.now().millisecondsSinceEpoch}';
        final created = await products.create(
          ProductInput(
            name: name,
            salePrice: 1500,
            purchasePrice: 1000,
            initialStock: 4,
            lowStockThreshold: 2,
          ),
        );
        expect(created.currentStock, 4);
        expect(created.lowStockThreshold, 2);

        await inventory.record(
          productId: created.id,
          type: MovementType.purchaseIn,
          quantity: 6,
          unitCost: 1000,
          note: 'live test',
        );
        expect((await products.get(created.id)).currentStock, 10);

        // A stock-out beyond what is available must be rejected by the server.
        await expectLater(
          inventory.record(productId: created.id, type: MovementType.adjustmentOut, quantity: 999),
          throwsA(isA<ApiException>()),
        );

        // Update clears optional fields sent as null.
        final updated = await products.update(
          created.id,
          ProductInput(name: name, salePrice: 1800),
        );
        expect(updated.salePrice, 1800);
        expect(updated.lowStockThreshold, isNull);
        expect(updated.purchasePrice, 0);

        final movements = await inventory.list(productId: created.id);
        expect(
          movements.items.map((m) => m.type),
          containsAll([MovementType.initial, MovementType.purchaseIn]),
        );
        expect(movements.items.first.productName, name);

        await products.deactivate(created.id);
        final inactive = await products.list(search: name, isActive: false);
        expect(inactive.items.map((p) => p.id), contains(created.id));
        expect((await products.list(search: name)).items, isEmpty);

        await products.reactivate(created.id);
        expect((await products.list(search: name)).items.map((p) => p.id), contains(created.id));

        // Leave the demo data tidy: hide the test product again.
        await products.deactivate(created.id);
      });

      test(
        'a product photo is uploaded, served back byte for byte, replaced and removed',
        () async {
          final client = await _loggedInClient();
          final products = ProductsApi(client.dio);

          final product = await products.create(
            ProductInput(
              name: 'zz-live-photo-${DateTime.now().millisecondsSinceEpoch}',
              salePrice: 900,
            ),
          );
          expect(product.hasImage, isFalse);
          await expectLater(products.fetchImage(product.id), throwsA(isA<ApiException>()));

          final withPhoto = await products.uploadImage(product.id, tinyPng, 'photo.png');
          expect(withPhoto.hasImage, isTrue);
          expect(withPhoto.imageKey, endsWith('.png'));
          expect(await products.fetchImage(product.id), tinyPng);
          // The list carries the key too (that is what makes the app fetch and cache the photo).
          final listed = (await products.list(search: product.name)).items.single;
          expect(listed.imageKey, withPhoto.imageKey);

          // Replacing gives a new key, so the app never shows stale bytes from its cache.
          final replaced = await products.uploadImage(product.id, tinyPng, 'autre.png');
          expect(replaced.imageKey, isNot(withPhoto.imageKey));

          // Not an image, whatever it is called: refused, and the current photo stays.
          await expectLater(
            products.uploadImage(
              product.id,
              Uint8List.fromList('pas une image'.codeUnits),
              'x.png',
            ),
            throwsA(isA<ApiException>()),
          );
          expect((await products.get(product.id)).imageKey, replaced.imageKey);

          final removed = await products.deleteImage(product.id);
          expect(removed.hasImage, isFalse);
          await expectLater(products.fetchImage(product.id), throwsA(isA<ApiException>()));

          await products.deactivate(product.id);
        },
      );

      test(
        'a sale rung up offline keeps its date and is recorded even if the stock ran out since',
        () async {
          final client = await _loggedInClient();
          final products = ProductsApi(client.dio);
          final sales = SalesApi(client.dio);

          final product = await products.create(
            ProductInput(
              name: 'zz-live-offline-${DateTime.now().millisecondsSinceEpoch}',
              salePrice: 1000,
              initialStock: 1,
            ),
          );
          final threeHoursAgo = DateTime.now().toUtc().subtract(const Duration(hours: 3));
          CheckoutRequest request(String id) => CheckoutRequest(
            items: [CheckoutLine(productId: product.id, quantity: 3)],
            payments: const [CheckoutPayment(method: PaymentMethod.cash, amount: 3000)],
            clientRequestId: id,
          );

          // Rung up online, 3 units of a product with 1 in stock: refused.
          await expectLater(
            sales.checkout(request(generateRequestId())),
            throwsA(isA<ApiException>()),
          );

          // The same sale rung up offline already happened: recorded, dated when it really happened.
          final id = generateRequestId();
          final recorded = await sales.checkout(request(id).asOffline(threeHoursAgo));
          expect(recorded.soldAt.difference(threeHoursAgo).inSeconds.abs(), lessThan(2));
          expect((await products.get(product.id)).currentStock, -2);

          // Sending it again (its answer got lost) is recognised, not sold twice.
          final replay = await sales.checkout(request(id).asOffline(threeHoursAgo));
          expect(replay.id, recorded.id);
          expect((await products.get(product.id)).currentStock, -2);

          // A date far in the past is refused.
          await expectLater(
            sales.checkout(
              request(
                generateRequestId(),
              ).asOffline(DateTime.now().toUtc().subtract(const Duration(days: 61))),
            ),
            throwsA(isA<ApiException>()),
          );

          await sales.voidSale(recorded.id);
          expect((await products.get(product.id)).currentStock, 1);
          await products.deactivate(product.id);
        },
      );

      test('checkout is idempotent; credit sales and voiding work through the real API', () async {
        final client = await _loggedInClient();
        final products = ProductsApi(client.dio);
        final sales = SalesApi(client.dio);

        final profile = await AuthApi(client.dio).me();
        final business = await BusinessApi(client.dio).details(profile.activeBusinessId!);
        expect(business.name, isNotEmpty);

        final name = 'zz-live-pos-${DateTime.now().millisecondsSinceEpoch}';
        final product = await products.create(
          ProductInput(name: name, salePrice: 2000, purchasePrice: 1200, initialStock: 10),
        );
        CheckoutLine line(double quantity) =>
            CheckoutLine(productId: product.id, quantity: quantity);
        Future<double> stock() async => (await products.get(product.id)).currentStock;

        // Cash sale, then the exact same request again (network retry / double tap).
        final request = CheckoutRequest(
          items: [line(3)],
          payments: const [CheckoutPayment(method: PaymentMethod.cash, amount: 6000)],
          clientRequestId: generateRequestId(),
        );
        final first = await sales.checkout(request);
        final replay = await sales.checkout(request);
        expect(replay.id, first.id);
        expect(replay.saleNumber, first.saleNumber);
        expect(first.total, 6000);
        expect(first.amountDue, 0);
        expect(first.items.single.productName, name);
        expect(await stock(), 7);

        // Fully on credit: no payment at all, tied to an existing customer.
        final customers = await CustomersApi(client.dio).list(search: 'Mamadou');
        final mamadou = customers.items.firstWhere((c) => c.fullName.startsWith('Mamadou'));
        final onCredit = await sales.checkout(
          CheckoutRequest(
            items: [line(2)],
            customerId: mamadou.id,
            clientRequestId: generateRequestId(),
          ),
        );
        expect(onCredit.amountPaid, 0);
        expect(onCredit.amountDue, 4000);
        expect(onCredit.payments, isEmpty);
        expect(onCredit.customer!.fullName, mamadou.fullName);
        expect(await stock(), 5);

        // Underpaid with no customer: the server refuses.
        await expectLater(
          sales.checkout(CheckoutRequest(items: [line(1)], clientRequestId: generateRequestId())),
          throwsA(isA<ApiException>()),
        );
        expect(await stock(), 5);

        expect((await sales.list()).items.map((s) => s.id), containsAll([first.id, onCredit.id]));
        expect((await sales.get(onCredit.id)).customer, isNotNull);

        // Voiding restores the stock and cancels the debt.
        await sales.voidSale(first.id);
        await sales.voidSale(onCredit.id);
        expect(await stock(), 10);
        expect((await sales.get(first.id)).isVoid, isTrue);
        await expectLater(sales.voidSale(first.id), throwsA(isA<ApiException>()));

        await products.deactivate(product.id);
      });

      test(
        'direct payments: settings, declaration, one-use references, owner verification',
        () async {
          final client = await _loggedInClient();
          final options = PaymentMethodsApi(client.dio);
          final payments = PaymentsApi(client.dio);
          final sales = SalesApi(client.dio);

          // A method that was used stays for the history, so one test method is reused and switched off.
          final existing =
              (await options.list()).where((o) => o.displayName == 'zz-live-test').firstOrNull;
          final option =
              existing ??
              await options.create(
                const PaymentOptionInput(
                  provider: PaymentProvider.merchantCode,
                  displayName: 'zz-live-test',
                  accountName: 'Test',
                  merchantCode: 'ZZ-LIVE-1',
                ),
              );
          if (!option.isActive) await options.setActive(option.id, true);

          final water = (await ProductsApi(client.dio).list()).items.firstWhere(
            (p) => p.name == 'Eau minérale 1.5L',
          );
          final salesBefore = (await sales.list()).total;
          final key = generateRequestId();
          final basket = [CheckoutLine(productId: water.id, quantity: 1)];

          // The server prices the basket; the same key returns the same payment.
          final started = await payments.start(
            items: basket,
            paymentMethodId: option.id,
            clientRequestId: key,
          );
          expect(started.status, PaymentStatus.pending);
          expect(started.amount, water.salePrice);
          expect(started.method.merchantCode, 'ZZ-LIVE-1');
          expect(started.method.instructionSteps, isNotEmpty);
          expect(
            (await payments.start(
              items: basket,
              paymentMethodId: option.id,
              clientRequestId: key,
            )).id,
            started.id,
          );

          // Declaring: the exact amount and a real reference are required.
          final reference = 'ZZLIVE${DateTime.now().millisecondsSinceEpoch}';
          DeclarationInput declaration(double amount, String ref) => DeclarationInput(
            payerPhone: '655112233',
            transactionReference: ref,
            amountSent: amount,
          );
          await expectLater(
            payments.submit(started.id, declaration(started.amount + 1, reference)),
            throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
          );
          await expectLater(
            payments.submit(started.id, declaration(started.amount, 'ab')),
            throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
          );
          final submitted = await payments.submit(
            started.id,
            declaration(started.amount, reference),
          );
          expect(submitted.status, PaymentStatus.submitted);
          expect(submitted.declaration!.transactionReference, reference);
          expect((await sales.list()).total, salesBefore, reason: 'a declaration sells nothing');

          // A transaction reference proves one payment only.
          final other = await payments.start(
            items: basket,
            paymentMethodId: option.id,
            clientRequestId: generateRequestId(),
          );
          await expectLater(
            payments.submit(other.id, declaration(other.amount, reference.toLowerCase())),
            throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
          );
          await payments.cancel(other.id);

          expect((await payments.summary()).submitted, greaterThanOrEqualTo(1));
          expect(
            (await payments.list(status: PaymentStatus.submitted)).items.map((p) => p.id),
            contains(started.id),
          );

          // The owner verifies: the sale is recorded once.
          final verified = await payments.verify(started.id);
          expect(verified.status, PaymentStatus.verified);
          expect(verified.saleId, isNotNull);
          expect(verified.sale!.total, water.salePrice);
          expect((await payments.verify(started.id)).saleId, verified.saleId);
          expect((await sales.list()).total, salesBefore + 1);

          // Clean up: void the sale (stock comes back) and switch the test method off.
          await sales.voidSale(verified.saleId!);
          await options.setActive(option.id, false);
        },
      );

      test(
        'customers, debts, expenses and the dashboard round-trip through the real API',
        () async {
          final client = await _loggedInClient();
          final customers = CustomersApi(client.dio);
          final expenses = ExpensesApi(client.dio);
          final dashboard = DashboardApi(client.dio);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          // A throw-away customer: created, edited (clearing a field), then deleted.
          final stamp = DateTime.now().millisecondsSinceEpoch;
          final temp = await customers.create(
            fullName: 'zz-live-client-$stamp',
            phone: '+224600000999',
            address: 'Kaloum',
          );
          expect(temp.address, 'Kaloum');
          expect(temp.hasDebt, isFalse);
          final edited = await customers.update(
            temp.id,
            CustomerInput(fullName: temp.fullName, phone: temp.phone),
          );
          expect(edited.address, isNull);
          expect(edited.phone, '+224600000999');
          await customers.delete(temp.id);
          await expectLater(customers.get(temp.id), throwsA(isA<ApiException>()));

          // Debts on the seeded demo customer: add one that is already late, then repay it in
          // two instalments. The balance ends where it started (only history lines are added).
          final mamadou = (await customers.list(search: 'Mamadou')).items.first;
          final before = mamadou.currentBalance;
          final dueTwoDaysAgo = today.subtract(const Duration(days: 2));
          await customers.grantCredit(
            mamadou.id,
            amount: 30000,
            dueDate: dueTwoDaysAgo,
            note: 'live test',
          );
          expect((await customers.get(mamadou.id)).currentBalance, before + 30000);

          final owed = (await customers.credits(mamadou.id)).where((c) => c.isOutstanding).toList();
          final lateOnes = owed.where((c) => c.isOverdue(now)).toList();
          expect(lateOnes, isNotEmpty);
          expect(lateOnes.any((c) => c.note == 'live test' && c.dueDate == dueTwoDaysAgo), isTrue);

          final overview = await customers.outstandingCredits();
          expect(overview.items.every((c) => c.isOutstanding), isTrue);
          expect(overview.items.any((c) => c.customer?.fullName == mamadou.fullName), isTrue);

          final summary = await dashboard.summary(DashboardPeriod.today);
          expect(summary.overdueCreditsCount, greaterThanOrEqualTo(1));
          expect(summary.outstandingCredits, greaterThanOrEqualTo(30000));

          await customers.recordPayment(
            mamadou.id,
            amount: 10000,
            method: PaymentMethod.mobileMoney,
            note: 'live test',
          );
          await expectLater(
            customers.recordPayment(
              mamadou.id,
              amount: before + 999999,
              method: PaymentMethod.cash,
            ),
            throwsA(isA<ApiException>()),
          );
          await customers.recordPayment(mamadou.id, amount: 20000, method: PaymentMethod.cash);
          expect((await customers.get(mamadou.id)).currentBalance, before);

          final statement = await customers.statement(mamadou.id);
          expect(statement.where((e) => e.isPayment && e.method == 'mobile_money'), isNotEmpty);
          expect(statement.where((e) => !e.isPayment && e.note == 'live test'), isNotEmpty);

          // A customer who has debts on record cannot be deleted.
          await expectLater(customers.delete(mamadou.id), throwsA(isA<ApiException>()));

          // Expenses: create, list with the period total, edit (clearing the description), delete.
          final created = await expenses.create(
            ExpenseInput(
              category: 'autre',
              amount: 1234,
              expenseDate: today,
              description: 'zz-live-expense',
            ),
          );
          expect(created.expenseDate, today);
          final page = await expenses.list(from: today, to: today);
          expect(page.items.map((e) => e.id), contains(created.id));
          expect(page.totalAmount, greaterThanOrEqualTo(1234));
          expect(
            (await dashboard.summary(DashboardPeriod.today)).expensesTotal,
            greaterThanOrEqualTo(1234),
          );

          final cleared = await expenses.update(
            created.id,
            ExpenseInput(category: 'transport', amount: 2000, expenseDate: today),
          );
          expect(cleared.description, isNull);
          expect(cleared.category, 'transport');
          expect((await expenses.get(created.id)).amount, 2000);

          await expenses.delete(created.id);
          final after = await expenses.list(from: today, to: today);
          expect(after.items.map((e) => e.id), isNot(contains(created.id)));

          // Every dashboard period and both widgets parse from real responses.
          for (final period in DashboardPeriod.values) {
            final s = await dashboard.summary(period);
            expect(s.ordersCount, greaterThanOrEqualTo(0));
            await dashboard.topProducts(period);
          }
          final chart = await dashboard.salesChart();
          expect(chart, hasLength(7));
          expect(chart.last.date, today);
        },
      );
    },
  );
}
