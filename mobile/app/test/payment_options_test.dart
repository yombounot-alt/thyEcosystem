import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/media/photo_picker.dart';
import 'package:thy_app/features/payments/data/payment_method_models.dart';

import 'fakes.dart';
import 'payment_helpers.dart';

void main() {
  late FakePaymentMethodsApi methods;

  setUp(() => methods = FakePaymentMethodsApi());

  Future<void> openSettings(
    WidgetTester tester, {
    FakeAuthApi? auth,
    FakePhotoPicker? picker,
  }) async {
    await pumpAuthenticatedApp(tester, paymentMethods: methods, authApi: auth, photoPicker: picker);
    await openTab(tester, 'Plus');
    await tester.tap(find.text('Moyens de paiement'));
    await tester.pumpAndSettle();
  }

  group('Paramètres → Moyens de paiement', () {
    testWidgets('start empty: nothing is preconfigured, the owner is invited to add theirs', (
      tester,
    ) async {
      await openSettings(tester);

      expect(find.text('Aucun moyen de paiement'), findsOneWidget);
      expect(find.textContaining('Orange Money'), findsWidgets); // in the explanation only
      expect(methods.all, isEmpty);
      expect(find.text('Ajouter un moyen de paiement'), findsOneWidget);
    });

    testWidgets('adds Orange Money with a holder and a number', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Ajouter un moyen de paiement'));
      await tester.pumpAndSettle();

      await typeInto(tester, 'Nom du titulaire', 'Aissatou Diallo');
      await typeInto(tester, 'Numéro Orange Money', '622 12 34 56');
      await tapVisible(tester, find.text('Enregistrer'));

      final saved = methods.created.single;
      expect(saved.provider, PaymentProvider.orangeMoney);
      expect(saved.accountName, 'Aissatou Diallo');
      expect(saved.phoneNumber, '622 12 34 56');
      expect(saved.isActive, isTrue);

      expect(find.text('Orange Money'), findsOneWidget);
      expect(find.text('Aissatou Diallo · 622 12 34 56'), findsOneWidget);
    });

    testWidgets('refuses an Orange Money option without a number, or with a wrong one', (
      tester,
    ) async {
      await openSettings(tester);
      await tester.tap(find.text('Ajouter un moyen de paiement'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Enregistrer'));
      expect(find.text('Saisissez le numéro.'), findsOneWidget);

      await typeInto(tester, 'Numéro Orange Money', '12ab');
      await tapVisible(tester, find.text('Enregistrer'));
      expect(find.text('Numéro invalide (6 à 15 chiffres).'), findsOneWidget);
      expect(methods.created, isEmpty);
    });

    testWidgets('a merchant code asks for the code, not for a number', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Ajouter un moyen de paiement'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Code marchand').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Code marchand'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Numéro Orange Money'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Nom du marchand'), findsOneWidget);

      await tapVisible(tester, find.text('Enregistrer'));
      expect(find.text('Saisissez le code marchand.'), findsOneWidget);

      await typeInto(tester, 'Nom du marchand', 'Boutique Demo');
      await typeInto(tester, 'Code marchand', 'MARCHAND-77');
      await tapVisible(tester, find.text('Enregistrer'));

      expect(methods.created.single.provider, PaymentProvider.merchantCode);
      expect(methods.created.single.merchantCode, 'MARCHAND-77');
      expect(methods.created.single.phoneNumber, isEmpty);
    });

    testWidgets('only accepts a USSD code made of digits, * # + and the known placeholders', (
      tester,
    ) async {
      await openSettings(tester);
      await tester.tap(find.text('Ajouter un moyen de paiement'));
      await tester.pumpAndSettle();
      await typeInto(tester, 'Numéro Orange Money', '622123456');

      await typeInto(tester, 'Code USSD « Payer maintenant » (facultatif)', 'tel:*144#');
      await tapVisible(tester, find.text('Enregistrer'));
      expect(find.textContaining('Seuls les chiffres'), findsOneWidget);
      expect(methods.created, isEmpty);

      await typeInto(
        tester,
        'Code USSD « Payer maintenant » (facultatif)',
        '*144*1*{numero}*{montant}#',
      );
      await tapVisible(tester, find.text('Enregistrer'));
      expect(methods.created.single.ussdCode, '*144*1*{numero}*{montant}#');
    });

    testWidgets('lists several accounts of one operator and switches them on and off', (
      tester,
    ) async {
      methods = FakePaymentMethodsApi(
        initial: [
          orangeOption(),
          testOption(
            id: 'orange-02',
            provider: PaymentProvider.orangeMoney,
            name: 'Orange Money 2',
            phone: '621 99 88 77',
          ),
        ],
      );
      await openSettings(tester);

      expect(find.text('Orange Money'), findsOneWidget);
      expect(find.text('Orange Money 2'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(methods.all.first.isActive, isFalse);
      expect(find.textContaining('désactivé'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(methods.all.first.isActive, isTrue);
    });

    testWidgets('edits an option: the number can change without touching the code', (tester) async {
      methods = FakePaymentMethodsApi(initial: [orangeOption()]);
      await openSettings(tester);

      await tester.tap(find.text('Orange Money'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier le moyen de paiement'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Numéro Orange Money'), findsOneWidget);

      await typeInto(tester, 'Numéro Orange Money', '621 00 00 09');
      await typeInto(tester, 'Instructions (facultatif)', 'Ouvrez *144#\nEnvoyez le montant');
      await tapVisible(tester, find.text('Enregistrer'));

      final saved = methods.updated['orange-01']!;
      expect(saved.phoneNumber, '621 00 00 09');
      expect(methods.all.single.instructionSteps, ['Ouvrez *144#', 'Envoyez le montant']);
      expect(find.text('Aissatou Diallo · 621 00 00 09'), findsOneWidget);
    });

    testWidgets('deletes an unused option, and says to deactivate one that was used', (
      tester,
    ) async {
      methods = FakePaymentMethodsApi(initial: [orangeOption(), momoOption()]);
      methods.used.add('momo-0001');
      await openSettings(tester);

      // Already used by a payment: the history points at it, so it cannot be deleted.
      await tester.tap(find.text('Mobile Money'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Supprimer ce moyen de paiement'));
      await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('désactivez-le plutôt'), findsOneWidget);
      expect(methods.deleted, isEmpty);

      // Never used: it goes.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Orange Money'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Supprimer ce moyen de paiement'));
      await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(methods.deleted, ['orange-01']);
      expect(find.text('Orange Money'), findsNothing);
      expect(find.text('Mobile Money'), findsOneWidget);
    });

    testWidgets('picks a logo and sends it after saving', (tester) async {
      final picker = FakePhotoPicker(PickedPhoto(bytes: tinyPng, filename: 'logo.png'));
      await openSettings(tester, picker: picker);
      await tester.tap(find.text('Ajouter un moyen de paiement'));
      await tester.pumpAndSettle();
      await typeInto(tester, 'Numéro Orange Money', '622123456');

      await tapVisible(tester, find.text('Choisir un logo'));
      expect(picker.requested, [PhotoSource.gallery]);
      await tapVisible(tester, find.text('Enregistrer'));

      expect(methods.logos.values.single, tinyPng);
    });

    testWidgets('a logo that is too heavy is refused before sending', (tester) async {
      final heavy = PickedPhoto(bytes: Uint8List(1024 * 1024 + 1), filename: 'big.png');
      await openSettings(tester, picker: FakePhotoPicker(heavy));
      await tester.tap(find.text('Ajouter un moyen de paiement'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Choisir un logo'));
      expect(find.textContaining('Logo trop lourd'), findsOneWidget);
    });

    testWidgets('a cashier cannot see or open the settings', (tester) async {
      methods = FakePaymentMethodsApi(initial: [orangeOption()]);
      await pumpAuthenticatedApp(
        tester,
        paymentMethods: methods,
        authApi: FakeAuthApi(role: 'cashier'),
      );
      await openTab(tester, 'Plus');

      expect(find.text('Paiements'), findsOneWidget);
      expect(find.text('Moyens de paiement'), findsNothing);
    });
  });
}
