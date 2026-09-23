import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/media/photo_picker.dart';
import 'package:thy_app/core/theme/formatters.dart';
import 'package:thy_app/features/payments/data/payment_models.dart';
import 'package:thy_app/features/products/data/product_models.dart';
import 'package:thy_app/features/sales/data/sale_models.dart';

import 'fakes.dart';
import 'payment_helpers.dart';

void main() {
  late List<Product> catalog;
  late FakeProductsApi productsApi;
  late FakeSalesApi salesApi;
  late FakePaymentMethodsApi methods;
  late FakePaymentsApi payments;
  late List<String> copied;
  late List<String> dialed;
  late List<String> shared;

  final money = formatMoney(10000, currency: 'GNF');

  setUp(() {
    catalog = paymentCatalog();
    productsApi = FakeProductsApi(catalog);
    salesApi = FakeSalesApi(catalog: catalog);
    methods = FakePaymentMethodsApi(initial: [orangeOption(), momoOption(), codeOption()]);
    payments = FakePaymentsApi(sales: salesApi, catalog: catalog, options: methods);
    copied = [];
    dialed = [];
    shared = [];
  });

  Future<void> pump(WidgetTester tester, {FakeAuthApi? auth, FakePhotoPicker? picker}) {
    return pumpAuthenticatedApp(
      tester,
      products: productsApi,
      sales: salesApi,
      paymentMethods: methods,
      payments: payments,
      copiedTexts: copied,
      dialedCodes: dialed,
      sharedTexts: shared,
      authApi: auth,
      photoPicker: picker,
    );
  }

  /// A payment the customer already declared, waiting for the owner (set up through the server).
  Future<ManualPayment> seedSubmitted({String reference = 'MP240921.SEED.01', int qty = 2}) async {
    final p = await payments.start(
      items: [CheckoutLine(productId: 'p1', quantity: qty.toDouble())],
      paymentMethodId: 'orange-01',
      clientRequestId: 'seed-${payments.all.length}-$reference',
    );
    return payments.submit(
      p.id,
      DeclarationInput(
        payerPhone: '655 11 22 33',
        transactionReference: reference,
        amountSent: p.amount,
        payerName: 'Mamadou Bah',
      ),
    );
  }

  Future<void> openPayments(WidgetTester tester) async {
    await openTab(tester, 'Plus');
    await tester.tap(find.text('Paiements'));
    await tester.pumpAndSettle();
  }

  Future<void> toDeclaration(WidgetTester tester, {String option = 'Orange Money'}) async {
    await toMobilePayment(tester);
    await chooseOption(tester, option);
    await tapVisible(tester, find.text('J’ai effectué le paiement'));
  }

  // ==========================================================================================
  group('the customer chooses how to pay', () {
    testWidgets('sees the owner’s options as cards and the exact amount — nothing is started yet', (
      tester,
    ) async {
      await pump(tester);
      await toMobilePayment(tester);

      expect(find.text('Choisir un moyen de paiement'), findsOneWidget);
      expect(find.text('Choisissez votre moyen de paiement'), findsOneWidget);
      expect(find.text(money), findsOneWidget);
      for (final name in ['Orange Money', 'Mobile Money', 'Code marchand']) {
        expect(find.widgetWithText(ListTile, name), findsOneWidget);
      }
      expect(find.text('Copier le numéro'), findsNothing);
      expect(payments.all, isEmpty, reason: 'no payment exists until a method is chosen');
    });

    testWidgets('is only offered the options the owner switched on', (tester) async {
      methods = FakePaymentMethodsApi(
        initial: [orangeOption(), momoOption(active: false), codeOption()],
      );
      payments = FakePaymentsApi(sales: salesApi, catalog: catalog, options: methods);
      await pump(tester);
      await toMobilePayment(tester);

      expect(find.widgetWithText(ListTile, 'Orange Money'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Mobile Money'), findsNothing);
    });

    testWidgets('shows where to send the money, how much, and the steps', (tester) async {
      await pump(tester);
      await toMobilePayment(tester);
      await chooseOption(tester, 'Orange Money');

      expect(find.text('Aissatou Diallo'), findsWidgets);
      expect(find.text('622 12 34 56'), findsOneWidget);
      expect(find.text('Montant à envoyer'), findsOneWidget);
      expect(find.text(money), findsWidgets);
      expect(find.text('Envoyez exactement ce montant.'), findsOneWidget);
      expect(find.text('Ouvrez Orange Money.'), findsOneWidget);
      expect(find.text('8.'), findsOneWidget);
      expect(find.text('Votre paiement sera vérifié avant validation.'), findsOneWidget);

      final started = payments.all.single;
      expect(started.status, PaymentStatus.pending);
      expect(started.amount, 10000);
      expect(salesApi.recordedCount, 0, reason: 'nothing is sold before the owner verifies');
    });

    testWidgets('copies the number (digits only) and says so', (tester) async {
      await pump(tester);
      await toMobilePayment(tester);
      await chooseOption(tester, 'Orange Money');

      await tapVisible(tester, find.text('Copier le numéro'));

      expect(copied, ['622123456']);
      expect(find.text('Numéro copié'), findsOneWidget);
    });

    testWidgets('copies the exact amount', (tester) async {
      await pump(tester);
      await toMobilePayment(tester);
      await chooseOption(tester, 'Orange Money');

      await tapVisible(tester, find.text('Copier le montant'));

      expect(copied, ['10000']);
      expect(find.text('Montant copié'), findsOneWidget);
    });

    testWidgets('a merchant code shows the code and copies the code', (tester) async {
      await pump(tester);
      await toMobilePayment(tester);
      await chooseOption(tester, 'Code marchand');

      expect(find.text('MARCHAND-77'), findsOneWidget);
      expect(find.text('Copier le numéro'), findsNothing);
      await tapVisible(tester, find.text('Copier le code'));

      expect(copied, ['MARCHAND-77']);
      expect(find.text('Code copié'), findsOneWidget);
    });

    testWidgets(
      '“Payer maintenant” exists only when the owner configured a USSD code, and dials it filled in',
      (tester) async {
        methods = FakePaymentMethodsApi(
          initial: [orangeOption(ussd: '*144*1*{numero}*{montant}#'), momoOption()],
        );
        payments = FakePaymentsApi(sales: salesApi, catalog: catalog, options: methods);
        await pump(tester);
        await toMobilePayment(tester);

        await chooseOption(tester, 'Mobile Money');
        expect(find.text('Payer maintenant'), findsNothing); // no code configured: none is invented

        await chooseOption(tester, 'Orange Money');
        await tapVisible(tester, find.text('Payer maintenant'));
        expect(dialed, ['*144*1*622123456*10000#']);
      },
    );

    testWidgets('changing method drops the earlier undeclared payment and starts another', (
      tester,
    ) async {
      await pump(tester);
      await toMobilePayment(tester);
      await chooseOption(tester, 'Orange Money');
      final first = payments.lastId;

      await chooseOption(tester, 'Mobile Money');

      expect(payments.all, hasLength(2));
      expect(payments.cancelled, [first]);
      expect(find.text('666 00 00 01'), findsOneWidget);
      expect(find.text('622 12 34 56'), findsNothing);
    });

    testWidgets('when nothing is configured, the owner is sent to the settings', (tester) async {
      methods = FakePaymentMethodsApi();
      payments = FakePaymentsApi(sales: salesApi, catalog: catalog, options: methods);
      await pump(tester);
      await toMobilePayment(tester);

      expect(find.text('Aucun moyen de paiement n’est proposé pour le moment.'), findsOneWidget);
      await tester.tap(find.text('Configurer mes moyens de paiement'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun moyen de paiement'), findsOneWidget); // the settings screen
    });

    testWidgets('a cashier is told to ask the owner instead', (tester) async {
      methods = FakePaymentMethodsApi()..activeOnly = true;
      payments = FakePaymentsApi(sales: salesApi, catalog: catalog, options: methods);
      await pump(tester, auth: FakeAuthApi(role: 'cashier'));
      await toMobilePayment(tester);

      expect(find.textContaining('Demandez au propriétaire'), findsOneWidget);
      expect(find.text('Configurer mes moyens de paiement'), findsNothing);
    });

    testWidgets('says so when the server cannot be reached, and starts nothing', (tester) async {
      await pump(tester);
      await toMobilePayment(tester);
      payments.networkDown = true;

      await chooseOption(tester, 'Orange Money');

      expect(find.textContaining('Impossible de contacter le serveur'), findsOneWidget);
      expect(payments.all, isEmpty);
    });
  });

  // ==========================================================================================
  group('“J’ai effectué le paiement”: the declaration', () {
    testWidgets('needs the payer’s number, the reference and the exact amount', (tester) async {
      await pump(tester);
      await toDeclaration(tester);

      await tapVisible(tester, find.text('Envoyer la déclaration'));
      expect(find.text('Saisissez le numéro utilisé pour payer.'), findsOneWidget);
      expect(find.text('La référence de transaction est obligatoire.'), findsOneWidget);

      await fillDeclaration(tester, amount: '9000');
      await tapVisible(tester, find.text('Envoyer la déclaration'));
      expect(find.text('Le montant doit être exactement $money.'), findsOneWidget);

      await fillDeclaration(tester, phone: 'abc', amount: '10000');
      await tapVisible(tester, find.text('Envoyer la déclaration'));
      expect(find.text('Numéro invalide (6 à 15 chiffres).'), findsOneWidget);

      expect(payments.submitCalls, isEmpty);
    });

    testWidgets('records the declaration: waiting for the owner, nothing sold, the till freed', (
      tester,
    ) async {
      await pump(tester);
      await toDeclaration(tester);
      expect(find.text('Moyen de paiement utilisé'), findsOneWidget);
      expect(find.textContaining('Orange Money · '), findsOneWidget);

      await fillDeclaration(tester, reference: 'MP240921.1234.A56789', name: 'Mamadou Bah');
      await tapVisible(tester, find.text('Envoyer la déclaration'));

      expect(find.text('Paiement envoyé – En attente de vérification'), findsOneWidget);
      expect(find.text('MP240921.1234.A56789'), findsOneWidget);
      expect(find.text('Mamadou Bah'), findsOneWidget);
      expect(payments.all.single.status, PaymentStatus.submitted);
      expect(salesApi.recordedCount, 0, reason: 'a declaration is not a payment');

      // The basket lives in the payment now: a new sale starts empty.
      await tester.tap(find.text('Nouvelle vente'));
      await tester.pumpAndSettle();
      expect(find.text('Voir le panier'), findsNothing);
    });

    testWidgets('a double tap sends the declaration once', (tester) async {
      await pump(tester);
      await toDeclaration(tester);
      await fillDeclaration(tester);

      final button = find.text('Envoyer la déclaration');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(payments.submitCalls, hasLength(1));
      expect(payments.all, hasLength(1));
    });

    testWidgets('a transaction reference already used is refused, however it is written', (
      tester,
    ) async {
      await seedSubmitted(reference: 'OM240921ABC1');
      await pump(tester);
      await toDeclaration(tester);
      await fillDeclaration(tester, reference: 'om240921 abc1');

      await tapVisible(tester, find.text('Envoyer la déclaration'));

      expect(
        find.text('Cette référence de transaction a déjà été utilisée pour un autre paiement.'),
        findsOneWidget,
      );
      expect(find.text('Envoyer la déclaration'), findsOneWidget, reason: 'still on the form');
      expect(payments.all.last.status, PaymentStatus.pending);
    });

    testWidgets('sends a proof picture with the declaration, and the owner sees it', (
      tester,
    ) async {
      final picker = FakePhotoPicker(PickedPhoto(bytes: tinyPng, filename: 'preuve.png'));
      await pump(tester, picker: picker);
      await toDeclaration(tester);
      await fillDeclaration(tester);

      await tapVisible(tester, find.text('Choisir une image'));
      expect(find.text('Retirer'), findsOneWidget);
      await tapVisible(tester, find.text('Envoyer la déclaration'));

      expect(payments.all.single.hasProof, isTrue);
      expect(find.text('Preuve'), findsOneWidget);
      // …but a picture validates nothing.
      expect(payments.all.single.status, PaymentStatus.submitted);
    });

    testWidgets('an oversized proof is refused before sending', (tester) async {
      final picker = FakePhotoPicker(
        PickedPhoto(bytes: Uint8List(3 * 1024 * 1024 + 1), filename: 'big.png'),
      );
      await pump(tester, picker: picker);
      await toDeclaration(tester);

      await tapVisible(tester, find.text('Choisir une image'));

      expect(find.textContaining('Image trop lourde'), findsOneWidget);
      expect(find.text('Retirer'), findsNothing);
    });
  });

  // ==========================================================================================
  group('the owner verifies', () {
    testWidgets('validating records the sale and confirms the payment', (tester) async {
      final seeded = await seedSubmitted(reference: 'MP240921.SEED.01');
      await pump(tester);
      await openPayments(tester);
      await tester.tap(find.text('$money · Orange Money'));
      await tester.pumpAndSettle();

      expect(find.text('Paiement envoyé – En attente de vérification'), findsOneWidget);
      expect(find.text('Valider le paiement'), findsOneWidget);
      expect(salesApi.recordedCount, 0);

      await tester.tap(find.text('Valider le paiement'));
      await tester.pumpAndSettle();
      expect(find.text('Valider ce paiement ?'), findsOneWidget);
      expect(find.textContaining('MP240921.SEED.01'), findsWidgets);
      expect(find.textContaining('avez bien reçu $money'), findsOneWidget);

      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Valider le paiement')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Paiement confirmé'), findsOneWidget);
      expect(find.text('La vente VTE-0001 est enregistrée.'), findsOneWidget);
      expect(payments.verified, [seeded.id]);
      expect(salesApi.recordedCount, 1);
      expect(salesApi.requests.single.payments.single.method, 'mobile_money');
    });

    testWidgets('“Pas encore” leaves the payment waiting', (tester) async {
      await seedSubmitted();
      await pump(tester);
      await openPayments(tester);
      await tester.tap(find.text('$money · Orange Money'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Valider le paiement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pas encore'));
      await tester.pumpAndSettle();

      expect(payments.verified, isEmpty);
      expect(salesApi.recordedCount, 0);
      expect(find.text('Paiement envoyé – En attente de vérification'), findsOneWidget);
    });

    testWidgets('after validating, the receipt can be opened and the customer told', (
      tester,
    ) async {
      await seedSubmitted();
      await pump(tester);
      await openPayments(tester);
      await tester.tap(find.text('$money · Orange Money'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider le paiement'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Valider le paiement')),
      );
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Envoyer la confirmation au client'));
      expect(shared.single, contains('a été confirmé'));

      await tapVisible(tester, find.text('Voir le reçu'));
      expect(find.text('VTE-0001'), findsOneWidget);
    });

    testWidgets('refusing with a reason shows it, sells nothing, and lets the payer correct', (
      tester,
    ) async {
      await seedSubmitted(reference: 'WRONG-REF-1');
      await pump(tester);
      await openPayments(tester);
      await tester.tap(find.text('$money · Orange Money'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Refuser'));
      expect(find.text('Refuser ce paiement'), findsOneWidget);
      await tester.tap(find.text('Montant incorrect'));
      await tester.pump();
      await tester.tap(find.text('Refuser le paiement'));
      await tester.pumpAndSettle();

      expect(find.text('Paiement refusé'), findsOneWidget);
      expect(find.text('Motif : Montant incorrect'), findsOneWidget);
      expect(payments.rejected.single.reason, 'Montant incorrect');
      expect(salesApi.recordedCount, 0);

      // The payer corrects the reference and declares again.
      await tapVisible(tester, find.text('Corriger et renvoyer'));
      expect(find.textContaining('Refusé : Montant incorrect'), findsOneWidget);
      await typeInto(tester, 'Référence / ID de la transaction', 'GOOD-REF-2');
      await tapVisible(tester, find.text('Envoyer la déclaration'));

      expect(find.text('Paiement envoyé – En attente de vérification'), findsOneWidget);
      expect(find.text('GOOD-REF-2'), findsOneWidget);
    });

    testWidgets('refusing needs no reason, and the customer can be told', (tester) async {
      await seedSubmitted();
      await pump(tester);
      await openPayments(tester);
      await tester.tap(find.text('$money · Orange Money'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Refuser'));
      await tester.tap(find.text('Refuser le paiement'));
      await tester.pumpAndSettle();
      expect(find.text('Paiement refusé'), findsOneWidget);

      await tapVisible(tester, find.text('Informer le client'));
      expect(shared.single, contains('n’a pas pu être confirmé'));
    });

    testWidgets('an unpaid payment can be cancelled: nothing is sold, and it cannot be validated', (
      tester,
    ) async {
      final p = await payments.start(
        items: const [CheckoutLine(productId: 'p1', quantity: 2)],
        paymentMethodId: 'orange-01',
        clientRequestId: 'pending-payment-1',
      );
      await pump(tester);
      await openPayments(tester);
      await tester.tap(find.text('$money · Orange Money'));
      await tester.pumpAndSettle();
      expect(find.text('Valider le paiement'), findsNothing, reason: 'nothing was declared yet');

      await tapVisible(tester, find.text('Annuler ce paiement'));
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Annuler le paiement')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Paiement annulé'), findsOneWidget);
      expect(payments.cancelled, [p.id]);
      expect(salesApi.recordedCount, 0);
    });

    testWidgets('a cashier can see a declared payment but not decide it', (tester) async {
      await seedSubmitted();
      methods.activeOnly = true;
      await pump(tester, auth: FakeAuthApi(role: 'cashier'));
      await openPayments(tester);
      await tester.tap(find.text('$money · Orange Money'));
      await tester.pumpAndSettle();

      expect(find.text('En attente de la vérification du propriétaire.'), findsOneWidget);
      expect(find.text('Valider le paiement'), findsNothing);
      expect(find.text('Refuser'), findsNothing);
    });
  });

  // ==========================================================================================
  group('Paiements: the list, the badges, the banner', () {
    testWidgets('lists every payment with its status badge and filters by status', (tester) async {
      await seedSubmitted(reference: 'REF-SUBMITTED-1'); // → submitted
      await seedSubmitted(reference: 'REF-VERIFIED-2'); // → verified
      await payments.verify(payments.lastId);
      await seedSubmitted(reference: 'REF-REJECTED-3'); // → rejected
      await payments.reject(payments.lastId, reason: 'Montant incorrect');
      await payments.start(
        items: const [CheckoutLine(productId: 'p1', quantity: 2)],
        paymentMethodId: 'orange-01',
        clientRequestId: 'pending-x-1',
      ); // → pending
      await pump(tester);
      await openPayments(tester);

      Finder badge(String label) =>
          find.descendant(of: find.byType(ListTile), matching: find.text(label));
      expect(badge('Vérification en cours'), findsOneWidget);
      expect(badge('Payé'), findsOneWidget);
      expect(badge('Refusé'), findsOneWidget);
      expect(badge('En attente'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'À vérifier'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      expect(badge('Vérification en cours'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Payés'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      expect(badge('Payé'), findsOneWidget);
    });

    testWidgets('says so when there is nothing', (tester) async {
      await pump(tester);
      await openPayments(tester);
      expect(find.text('Aucun paiement.'), findsOneWidget);
    });

    testWidgets('tells the owner how many payments wait for verification, everywhere', (
      tester,
    ) async {
      await seedSubmitted(reference: 'REF-A-000001');
      await seedSubmitted(reference: 'REF-B-000002');
      await pump(tester);

      expect(find.text('2 paiements à vérifier'), findsOneWidget); // banner above the tabs
      expect(
        find.descendant(of: find.byType(NavigationBar), matching: find.byType(Badge)),
        findsWidgets,
      );

      await tester.tap(find.text('2 paiements à vérifier'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'À vérifier')).selected,
        isTrue,
      );
    });

    testWidgets('the banner goes away once the payment is dealt with', (tester) async {
      await seedSubmitted();
      await pump(tester);
      expect(find.text('1 paiement à vérifier'), findsOneWidget);

      await tester.tap(find.text('1 paiement à vérifier'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider le paiement'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Valider le paiement')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('paiement à vérifier'), findsNothing);
      expect(find.textContaining('paiements à vérifier'), findsNothing);
    });

    testWidgets('a cashier sees no banner and no count', (tester) async {
      await seedSubmitted();
      await pump(tester, auth: FakeAuthApi(role: 'cashier'));

      expect(find.textContaining('à vérifier'), findsNothing);
    });
  });

  // ==========================================================================================
  group('models', () {
    Map<String, dynamic> json({String status = 'submitted'}) => {
      'id': 'p-1',
      'status': status,
      'amount': 250000,
      'currency': 'GNF',
      'createdAt': '2026-09-21T09:00:00.000Z',
      'method': {
        'id': 'opt-1',
        'provider': 'orange_money',
        'displayName': 'Orange Money',
        'accountName': 'Aissatou Diallo',
        'phoneNumber': '622 12 34 56',
        'merchantCode': null,
        'instructionSteps': ['Ouvrez Orange Money.'],
        'ussdDial': null,
        'hasLogo': false,
      },
      'declaration': {
        'payerName': null,
        'payerPhone': '655 11 22 33',
        'transactionReference': 'REF12345',
        'amountSent': 250000,
        'paidAt': '2026-09-21T08:55:00.000Z',
        'submittedAt': '2026-09-21T09:01:00.000Z',
      },
      'hasProof': true,
      'saleId': null,
      'sale': null,
      'needsAttention': false,
    };

    test('reads what the server sends', () {
      final p = ManualPayment.fromJson(json());
      expect(p.amount, 250000);
      expect(p.method.destination, '622 12 34 56');
      expect(p.declaration!.transactionReference, 'REF12345');
      expect(p.declaration!.payerName, isNull);
      expect(p.hasProof, isTrue);
      expect(p.isSubmitted, isTrue);
      expect(p.canDeclare, isFalse);
    });

    test('a payment can be declared while pending or after a refusal only', () {
      expect(ManualPayment.fromJson(json(status: 'pending')).canDeclare, isTrue);
      expect(ManualPayment.fromJson(json(status: 'rejected')).canDeclare, isTrue);
      for (final s in ['submitted', 'verified', 'cancelled']) {
        expect(ManualPayment.fromJson(json(status: s)).canDeclare, isFalse, reason: s);
      }
    });

    test('a merchant code is sent to the code, everything else to the number', () {
      final code = PaymentOptionSnapshot.fromJson({
        'provider': 'merchant_code',
        'displayName': 'Code marchand',
        'merchantCode': 'MARCHAND-77',
        'phoneNumber': null,
        'instructionSteps': <String>[],
        'hasLogo': false,
      });
      expect(code.destination, 'MARCHAND-77');
    });

    test('the labels behind the badges', () {
      expect(PaymentStatus.label('pending'), 'En attente');
      expect(PaymentStatus.label('submitted'), 'Vérification en cours');
      expect(PaymentStatus.label('verified'), 'Payé');
      expect(PaymentStatus.label('rejected'), 'Refusé');
      expect(PaymentStatus.label('cancelled'), 'Annulé');
    });

    test('the summary counts each status, and missing ones are zero', () {
      final s = PaymentSummary.fromJson({'submitted': 3, 'verified': 12});
      expect(s.submitted, 3);
      expect(s.verified, 12);
      expect(s.pending, 0);
      expect(PaymentSummary.zero.submitted, 0);
    });

    test('the declaration sent to the server is trimmed and only carries what was filled in', () {
      final json =
          DeclarationInput(
            payerPhone: ' 655 11 22 33 ',
            transactionReference: ' REF12345 ',
            amountSent: 250000,
            payerName: '   ',
          ).toJson();
      expect(json, {
        'payerPhone': '655 11 22 33',
        'transactionReference': 'REF12345',
        'amountSent': 250000,
      });
    });
  });
}
