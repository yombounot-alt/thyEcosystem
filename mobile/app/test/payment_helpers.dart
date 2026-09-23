import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/features/payments/data/payment_method_models.dart';
import 'package:thy_app/features/products/data/product_models.dart';

import 'fakes.dart';

/// A payment option as the owner would have typed it. The values are test data: the app has no
/// built-in number or code of any kind.
PaymentOption testOption({
  required String id,
  required String provider,
  String? name,
  String? holder,
  String? phone,
  String? code,
  String? ussd,
  bool active = true,
  String? instructions,
}) {
  return PaymentOption(
    id: id,
    provider: provider,
    displayName: name ?? PaymentProvider.label(provider),
    accountName: holder,
    phoneNumber: phone,
    merchantCode: code,
    instructions: instructions,
    instructionSteps:
        instructions == null
            ? FakePaymentMethodsApi.defaultSteps(provider)
            : instructions.split('\n'),
    ussdCode: ussd,
    hasLogo: false,
    isActive: active,
    updatedAt: DateTime.utc(2026, 9, 21, 10),
  );
}

PaymentOption orangeOption({bool active = true, String? ussd}) => testOption(
  id: 'orange-01',
  provider: PaymentProvider.orangeMoney,
  holder: 'Aissatou Diallo',
  phone: '622 12 34 56',
  ussd: ussd,
  active: active,
);

PaymentOption momoOption({bool active = true}) => testOption(
  id: 'momo-0001',
  provider: PaymentProvider.mobileMoney,
  holder: 'Aissatou Diallo',
  phone: '666 00 00 01',
  active: active,
);

PaymentOption codeOption({bool active = true}) => testOption(
  id: 'code-0001',
  provider: PaymentProvider.merchantCode,
  holder: 'Boutique Demo',
  code: 'MARCHAND-77',
  active: active,
);

List<Product> paymentCatalog() => [
  testProduct(id: 'p1', name: 'Eau minérale 1.5L', stock: 20, salePrice: 5000),
  testProduct(id: 'p2', name: 'Sucre en poudre 1kg', stock: 10, salePrice: 8500),
];

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// Taps [finder] after scrolling it into view (forms are longer than a short screen).
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> typeInto(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

/// From the Caisse: rings up [times] waters, opens the payment screen and picks "Paiement mobile".
Future<void> toMobilePayment(WidgetTester tester, {int times = 2}) async {
  await openTab(tester, 'Caisse');
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text('Eau minérale 1.5L'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Voir le panier'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('ENCAISSER'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ChoiceChip, 'Paiement mobile'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choisir le moyen de paiement'));
  await tester.pumpAndSettle();
}

/// Picks a card on the "Choisir un moyen de paiement" screen.
Future<void> chooseOption(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(ListTile, name));
  await tester.pumpAndSettle();
}

/// Fills the declaration form ("J'ai effectué le paiement").
Future<void> fillDeclaration(
  WidgetTester tester, {
  String phone = '655 11 22 33',
  String reference = 'OM240921ABC1',
  String? amount,
  String name = '',
}) async {
  await typeInto(tester, 'Numéro de téléphone utilisé pour payer', phone);
  await typeInto(tester, 'Référence / ID de la transaction', reference);
  if (amount != null) await typeInto(tester, 'Montant envoyé', amount);
  if (name.isNotEmpty) await typeInto(tester, 'Nom du payeur (facultatif)', name);
}
