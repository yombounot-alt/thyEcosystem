import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/theme/formatters.dart';
import 'package:thy_app/features/customers/application/reminder_text.dart';
import 'package:thy_app/features/customers/data/customer_models.dart';
import 'package:thy_app/features/dashboard/data/dashboard_models.dart';
import 'package:thy_app/features/expenses/application/expenses_providers.dart';
import 'package:thy_app/features/expenses/data/expense_models.dart';

import 'fakes.dart';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

Future<void> openFromMore(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('models and helpers', () {
    test('a credit is late only once its due day is over', () {
      final now = DateTime(2026, 9, 19, 15);
      CustomerCredit credit(DateTime? due, {String status = CreditStatus.open}) =>
          testCredit(id: 'c', customerId: 'x', remaining: 1000, dueDate: due, status: status);

      expect(credit(DateTime(2026, 9, 18)).isOverdue(now), isTrue);
      expect(credit(DateTime(2026, 9, 19)).isOverdue(now), isFalse); // due today
      expect(credit(DateTime(2026, 9, 20)).isOverdue(now), isFalse);
      expect(credit(null).isOverdue(now), isFalse);
      expect(credit(DateTime(2026, 9, 1), status: CreditStatus.paid).isOverdue(now), isFalse);
      expect(credit(DateTime(2026, 9, 1), status: CreditStatus.voided).isOverdue(now), isFalse);
      expect(
        credit(DateTime(2026, 9, 1), status: CreditStatus.partiallyPaid).isOverdue(now),
        isTrue,
      );
    });

    test('a date-only value keeps its calendar day', () {
      expect(parseDateOnly('2026-09-21T00:00:00.000Z'), DateTime(2026, 9, 21));
      expect(parseDateOnly(null), isNull);
    });

    test('statement entries parse both debts and payments', () {
      final debt = StatementEntry.fromJson({
        'kind': 'credit',
        'date': '2026-09-16T21:52:06.148Z',
        'originalAmount': '350000',
        'remainingAmount': '350000',
        'status': 'open',
        'note': 'Achat de matériaux',
      });
      expect(debt.isPayment, isFalse);
      expect(debt.amount, 350000);
      expect(debt.creditStatus, 'open');

      final payment = StatementEntry.fromJson({
        'kind': 'payment',
        'date': '2026-09-17T09:00:00.000Z',
        'amount': '150000',
        'method': 'cash',
      });
      expect(payment.isPayment, isTrue);
      expect(payment.amount, 150000);
      expect(payment.method, 'cash');
    });

    test('customer update payload clears emptied optional fields', () {
      const input = CustomerInput(fullName: 'Awa Sow');
      expect(input.toCreateJson(), {'fullName': 'Awa Sow'});
      expect(input.toUpdateJson(), {
        'fullName': 'Awa Sow',
        'phone': null,
        'address': null,
        'notes': null,
      });
    });

    test('the debt reminder names the customer, the shop, the amount and the due date', () {
      final text = buildDebtReminderText(
        customerName: 'Mamadou Diallo',
        businessName: 'Boutique Demo',
        owed: 200000,
        currency: 'GNF',
        dueDate: DateTime(2026, 9, 21),
      );
      expect(text, contains('Mamadou Diallo'));
      expect(text, contains('Boutique Demo'));
      expect(text, contains(formatMoney(200000)));
      expect(text, contains('21/09/2026'));

      final noDue = buildDebtReminderText(
        customerName: 'Awa',
        businessName: 'Boutique Demo',
        owed: 1000,
        currency: 'GNF',
      );
      expect(noDue, isNot(contains('échéance')));
    });

    test('expense periods cover the right calendar days', () {
      final now = DateTime(2026, 9, 19, 14, 30);
      expect(ExpensePeriod.today.range(now), (
        from: DateTime(2026, 9, 19),
        to: DateTime(2026, 9, 19),
      ));
      expect(ExpensePeriod.week.range(now), (
        from: DateTime(2026, 9, 13),
        to: DateTime(2026, 9, 19),
      ));
      expect(ExpensePeriod.month.range(now), (from: DateTime(2026, 9), to: DateTime(2026, 9, 19)));
      expect(ExpensePeriod.all.range(now), (from: null, to: null));
    });

    test('expense payloads format the day and clear an emptied description on update', () {
      final input = ExpenseInput(
        category: 'transport',
        amount: 15000,
        expenseDate: DateTime(2026, 9, 5),
      );
      expect(input.toCreateJson(), {
        'category': 'transport',
        'amount': 15000.0,
        'expenseDate': '2026-09-05',
      });
      expect(input.toUpdateJson()['description'], isNull);
      expect(input.toUpdateJson().containsKey('description'), isTrue);
    });

    test('an expense page carries the total of the whole period', () {
      final page = ExpensePage.fromJson({
        'items': [
          {
            'id': 'e1',
            'category': 'loyer',
            'amount': '5000',
            'description': null,
            'expenseDate': '2026-09-19T00:00:00.000Z',
          },
        ],
        'total': 2,
        'page': 1,
        'pageSize': 1,
        'totalAmount': 20000,
      });
      expect(page.items.single.expenseDate, DateTime(2026, 9, 19));
      expect(page.total, 2);
      expect(page.totalAmount, 20000);
    });

    test('the dashboard summary accepts whole numbers and negative profit', () {
      final summary = DashboardSummary.fromJson({
        'revenue': 31000,
        'cogs': 21000,
        'expensesTotal': 95000,
        'profit': -85000,
        'ordersCount': 1,
        'lowStockCount': 0,
        'outstandingCredits': 200000.5,
        'overdueCreditsCount': 0,
      });
      expect(summary.profit, -85000);
      expect(summary.outstandingCredits, 200000.5);
      expect(summary.hasAlerts, isFalse);
    });
  });

  group('Clients', () {
    late FakeCustomersApi customers;

    setUp(() {
      customers = FakeCustomersApi(
        [
          const Customer(
            id: 'c1',
            fullName: 'Mamadou Diallo',
            phone: '+224655555555',
            currentBalance: 200000,
          ),
          const Customer(id: 'c2', fullName: 'Fatoumata Bah', phone: null, currentBalance: 0),
        ],
        {
          'c1': [
            testCredit(
              id: 'cr1',
              customerId: 'c1',
              remaining: 150000,
              original: 200000,
              dueDate: _today.subtract(const Duration(days: 3)),
              note: 'Ciment',
            ),
            testCredit(
              id: 'cr2',
              customerId: 'c1',
              remaining: 50000,
              dueDate: _today.add(const Duration(days: 10)),
            ),
          ],
        },
      );
    });

    Future<void> openCustomers(WidgetTester tester, {List<String>? shared}) async {
      await pumpAuthenticatedApp(tester, customers: customers, sharedTexts: shared);
      await openFromMore(tester, 'Clients');
    }

    Future<void> openMamadou(WidgetTester tester, {List<String>? shared}) async {
      await openCustomers(tester, shared: shared);
      await tester.tap(find.text('Mamadou Diallo'));
      await tester.pumpAndSettle();
    }

    testWidgets('the list can be narrowed to customers who owe money', (tester) async {
      await openCustomers(tester);
      expect(find.text('Mamadou Diallo'), findsOneWidget);
      expect(find.text('Fatoumata Bah'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Endettés'));
      await tester.pumpAndSettle();

      expect(find.text('Mamadou Diallo'), findsOneWidget);
      expect(find.text('Fatoumata Bah'), findsNothing);
    });

    testWidgets('a customer can be created, and the form checks the name', (tester) async {
      await openCustomers(tester);
      await tester.tap(find.text('Client'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ajouter le client'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nom requis'), findsOneWidget);
      expect(customers.created, isEmpty);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Awa Sow');
      await tester.enterText(fields.at(1), '+224622222222');
      await tester.tap(find.text('Ajouter le client'));
      await tester.pumpAndSettle();

      expect(customers.created.single.fullName, 'Awa Sow');
      expect(customers.created.single.phone, '+224622222222');
      expect(customers.created.single.address, isNull);
      expect(find.text('Awa Sow'), findsOneWidget);
    });

    testWidgets('the detail shows what is owed, the debts and which one is late', (tester) async {
      await openMamadou(tester);

      expect(find.text(formatMoney(200000)), findsOneWidget); // header balance
      expect(
        find.textContaining('Reste ${formatMoney(150000)} sur ${formatMoney(200000)}'),
        findsOneWidget,
      );
      expect(find.text('En retard'), findsOneWidget);
      expect(find.text('Historique'), findsOneWidget);
    });

    testWidgets('a partial payment is recorded and lowers the balance', (tester) async {
      await openMamadou(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer un paiement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Montant reçu'), '50000');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Paiement mobile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();

      final payment = customers.payments.single;
      expect(payment.customerId, 'c1');
      expect(payment.amount, 50000);
      expect(payment.method, 'mobile_money');
      expect(find.text(formatMoney(150000)), findsOneWidget);
      expect(find.text('Paiement enregistré.'), findsOneWidget);
    });

    testWidgets('paying back more than is owed is refused before calling the server', (
      tester,
    ) async {
      await openMamadou(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer un paiement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Montant reçu'), '999999');
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('dépasse la dette'), findsOneWidget);
      expect(customers.payments, isEmpty);
    });

    testWidgets('paying everything (the default) settles the customer', (tester) async {
      await openMamadou(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer un paiement'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();

      expect(customers.payments.single.amount, 200000);
      expect(find.text('À jour'), findsOneWidget);
      final payButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enregistrer un paiement'),
      );
      expect(payButton.onPressed, isNull);
    });

    testWidgets('a debt not tied to a sale can be added', (tester) async {
      await openMamadou(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Ajouter une dette'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Montant dû'), '25000');
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();

      expect(customers.debts.single.amount, 25000);
      expect(customers.debts.single.dueDate, isNull);
      expect(find.text(formatMoney(225000)), findsOneWidget);
    });

    testWidgets('a reminder is shared with the amount and the earliest due date', (tester) async {
      final shared = <String>[];
      await openMamadou(tester, shared: shared);

      await tester.tap(find.text('Envoyer un rappel'));
      await tester.pumpAndSettle();

      expect(shared, hasLength(1));
      expect(shared.single, contains('Mamadou Diallo'));
      expect(shared.single, contains('Boutique Demo'));
      expect(shared.single, contains(formatMoney(200000)));
      expect(shared.single, contains(formatDay(_today.subtract(const Duration(days: 3)))));
    });

    testWidgets('a customer with debts cannot be deleted; one without can', (tester) async {
      await openMamadou(tester);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ne peut pas être supprimé'), findsOneWidget);
      expect(customers.deleted, isEmpty);
    });

    testWidgets('a customer with nothing attached is deleted and the list updates', (tester) async {
      await openCustomers(tester);
      await tester.tap(find.text('Fatoumata Bah'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(customers.deleted, ['c2']);
      expect(find.text('Fatoumata Bah'), findsNothing);
      expect(find.text('Mamadou Diallo'), findsOneWidget);
    });

    testWidgets('Créances totals what is owed, flags late debts and opens the customer', (
      tester,
    ) async {
      await pumpAuthenticatedApp(tester, customers: customers);
      await openFromMore(tester, 'Créances');

      expect(find.text(formatMoney(200000)), findsOneWidget); // total = 150 000 + 50 000
      expect(find.text('1 en retard'), findsOneWidget);
      expect(find.text('Mamadou Diallo'), findsNWidgets(2)); // one row per debt
      expect(find.text('En retard'), findsOneWidget); // only the debt due 3 days ago

      await tester.tap(find.text('Mamadou Diallo').first);
      await tester.pumpAndSettle();
      expect(find.text('Dettes en cours'), findsOneWidget);
    });
  });

  group('Dépenses', () {
    late FakeExpensesApi expenses;

    setUp(() {
      expenses = FakeExpensesApi([
        Expense(
          id: 'e1',
          category: 'transport',
          amount: 15000,
          description: 'Livraison',
          expenseDate: _today,
        ),
        Expense(
          id: 'e2',
          category: 'electricite',
          amount: 80000,
          description: 'Facture EDG',
          expenseDate: _today.subtract(const Duration(days: 40)),
        ),
      ]);
    });

    Future<void> openExpenses(WidgetTester tester) async {
      await pumpAuthenticatedApp(tester, expenses: expenses);
      await openFromMore(tester, 'Dépenses');
    }

    testWidgets('lists the month by default with its total, and "Tout" widens it', (tester) async {
      await openExpenses(tester);
      expect(find.textContaining('Livraison'), findsOneWidget);
      expect(find.textContaining('Facture EDG'), findsNothing);
      expect(find.text(formatMoney(15000)), findsNWidgets(2)); // total + the row

      await tester.tap(find.widgetWithText(ChoiceChip, 'Tout'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Facture EDG'), findsOneWidget);
      expect(find.text(formatMoney(95000)), findsOneWidget); // whole-period total
    });

    testWidgets('an expense can be recorded, with a required amount', (tester) async {
      await openExpenses(tester);
      await tester.tap(find.text('Dépense'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ajouter la dépense'));
      await tester.pumpAndSettle();
      expect(find.text('Montant requis'), findsOneWidget);
      expect(expenses.created, isEmpty);

      await tester.enterText(find.byType(TextFormField).first, '12 500');
      await tester.tap(find.text('Ajouter la dépense'));
      await tester.pumpAndSettle();

      final input = expenses.created.single;
      expect(input.category, 'transport');
      expect(input.amount, 12500);
      expect(input.expenseDate, _today);
      expect(input.description, isNull);
    });

    testWidgets('an expense can be edited', (tester) async {
      await openExpenses(tester);
      await tester.tap(find.textContaining('Livraison'));
      await tester.pumpAndSettle();

      expect(find.text('Modifier la dépense'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '20000');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(expenses.updated.single.amount, 20000);
      expect(expenses.updated.single.category, 'transport');
      expect(expenses.updated.single.description, 'Livraison');
    });

    testWidgets('an expense can be deleted after confirmation', (tester) async {
      await openExpenses(tester);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(expenses.deleted, ['e1']);
      expect(find.textContaining('Livraison'), findsNothing);
    });
  });

  group('Accueil (tableau de bord)', () {
    const busyDay = DashboardSummary(
      revenue: 31000,
      cogs: 21000,
      expensesTotal: 95000,
      profit: -85000,
      ordersCount: 1,
      lowStockCount: 1,
      outstandingCredits: 200000,
      overdueCreditsCount: 2,
    );

    testWidgets('shows the key figures, the finance breakdown and the best sellers', (
      tester,
    ) async {
      await pumpAuthenticatedApp(tester, dashboard: FakeDashboardApi(summary: busyDay));

      expect(find.textContaining('Bonjour, Tamba'), findsOneWidget);
      expect(find.text(formatMoney(31000)), findsNWidgets(2)); // KPI + finance breakdown
      expect(find.text(formatMoney(-85000)), findsNWidgets(2)); // profit: KPI + breakdown
      expect(find.text('Commandes'), findsOneWidget);
      expect(find.text('Coût des marchandises'), findsOneWidget);
      expect(find.text('Sucre en poudre 1kg'), findsOneWidget);
      expect(find.text('7 derniers jours'), findsOneWidget);
    });

    testWidgets('lists the alerts that need attention', (tester) async {
      await pumpAuthenticatedApp(tester, dashboard: FakeDashboardApi(summary: busyDay));

      expect(find.text('1 produit en stock faible'), findsOneWidget);
      expect(find.text('2 crédits client en retard'), findsOneWidget);
      expect(find.text('Créances en cours : ${formatMoney(200000)}'), findsOneWidget);
    });

    testWidgets('says so when there is nothing to worry about', (tester) async {
      await pumpAuthenticatedApp(tester);
      expect(find.text('Aucune alerte pour le moment.'), findsOneWidget);
    });

    testWidgets('the late-credits alert opens the debts overview', (tester) async {
      final customers = FakeCustomersApi(
        [const Customer(id: 'c1', fullName: 'Mamadou Diallo', phone: null, currentBalance: 50000)],
        {
          'c1': [
            testCredit(
              id: 'cr1',
              customerId: 'c1',
              remaining: 50000,
              dueDate: _today.subtract(const Duration(days: 5)),
            ),
          ],
        },
      );
      await pumpAuthenticatedApp(
        tester,
        customers: customers,
        dashboard: FakeDashboardApi(summary: busyDay),
      );

      await tester.tap(find.text('2 crédits client en retard'));
      await tester.pumpAndSettle();

      expect(find.text('Créances'), findsOneWidget);
      expect(find.text('Mamadou Diallo'), findsOneWidget);
    });

    testWidgets('switching the period reloads the figures for that period', (tester) async {
      final dashboard = FakeDashboardApi(summary: busyDay);
      await pumpAuthenticatedApp(tester, dashboard: dashboard);
      expect(dashboard.requestedPeriods, [DashboardPeriod.today]);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Semaine'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Année'));
      await tester.pumpAndSettle();

      expect(
        dashboard.requestedPeriods,
        containsAllInOrder([DashboardPeriod.week, DashboardPeriod.year]),
      );
    });

    testWidgets('"Nouvelle vente" jumps to the Caisse', (tester) async {
      await pumpAuthenticatedApp(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Nouvelle vente'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aucun produit à vendre'), findsOneWidget);
    });
  });
}
