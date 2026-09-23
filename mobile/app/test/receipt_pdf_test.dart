import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/features/business/data/business_api.dart';
import 'package:thy_app/features/sales/application/receipt_pdf.dart';
import 'package:thy_app/features/sales/data/sale_models.dart';

import 'fakes.dart';

const _business = BusinessDetails(
  id: 'b1',
  name: 'Boutique Démo',
  currency: 'GNF',
  address: 'Kaloum, Conakry',
  phone: '+224600000000',
);

Sale _sale({
  int items = 2,
  double discount = 0,
  double paid = 0,
  bool voided = false,
  bool withCustomer = false,
}) {
  final lines = [
    for (var i = 1; i <= items; i++)
      {
        // Accents, an apostrophe and a long name on purpose: the embedded font must draw them.
        'productNameSnapshot':
            i.isOdd ? 'Eau minérale 1,5 L — pack économique n°$i' : 'Crème à l\'ail $i',
        'unitPrice': '5000',
        'quantity': '2',
        'lineTotal': '10000',
      },
  ];
  final subtotal = 10000.0 * items;
  final total = subtotal - discount;
  return Sale.fromJson({
    'id': 's1',
    'saleNumber': 'VTE-0042',
    'subtotal': '$subtotal',
    'discountTotal': '$discount',
    'total': '$total',
    'amountPaid': '$paid',
    'amountDue': '${total - paid}',
    'status': voided ? 'void' : 'completed',
    'soldAt': '2026-09-19T10:30:00.000Z',
    if (withCustomer) 'customer': {'id': 'c1', 'fullName': 'Mamadou Diallo'},
    'items': lines,
    'payments': [
      if (paid > 0) {'method': 'cash', 'amount': '$paid'},
    ],
  });
}

String _latin1(Uint8List bytes) => latin1.decode(bytes, allowInvalid: true);

int _pageCount(Uint8List pdf) => RegExp(r'/Type\s*/Page(?!s)').allMatches(_latin1(pdf)).length;

/// Everything the `pdf` package prints while building (it reports glyphs the font cannot draw).
Future<List<String>> _capturePrints(Future<void> Function() body) async {
  final printed = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => printed.add(line)),
  );
  return printed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReceiptFonts fonts;

  setUpAll(() async {
    fonts = await loadReceiptFonts(rootBundle);
  });

  group('buildReceiptPdf', () {
    test('produces a real, single-page PDF with the font embedded', () async {
      final pdf = await buildReceiptPdf(_sale(paid: 20000), _business, fonts: fonts);

      expect(_latin1(pdf.sublist(0, 8)), startsWith('%PDF-'));
      expect(_latin1(pdf.sublist(pdf.length - 16)), contains('%%EOF'));
      expect(_pageCount(pdf), 1);
      // The TrueType program is embedded (a subset), so the PDF reads the same on any device.
      expect(_latin1(pdf), contains('/FontFile2'));
      expect(_latin1(pdf), contains('Roboto'));
      // A5 in PDF points (1 pt = 1/72 in): 419.5 × 595.3.
      final box = RegExp(
        r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
      ).firstMatch(_latin1(pdf));
      expect(box, isNotNull);
      expect(double.parse(box!.group(1)!), closeTo(419.5, 0.5));
      expect(double.parse(box.group(2)!), closeTo(595.3, 0.5));
    });

    test('draws every character of a French receipt (no glyph is missing from the font)', () async {
      final printed = await _capturePrints(() async {
        await buildReceiptPdf(
          _sale(items: 3, discount: 1000, paid: 5000, withCustomer: true),
          _business,
          fonts: fonts,
          change: 500,
        );
        await buildReceiptPdf(_sale(voided: true, paid: 20000), _business, fonts: fonts);
      });

      expect(printed.where((line) => line.contains('Unable to find a font')), isEmpty);
    });

    test('a long sale flows onto more pages instead of being cut off', () async {
      final pdf = await buildReceiptPdf(_sale(items: 60, paid: 600000), _business, fonts: fonts);

      expect(_pageCount(pdf), greaterThan(1));
    });

    test(
      'builds every variant: cash, credit with customer, discount, voided, no address',
      () async {
        final variants = <Sale>[
          _sale(paid: 20000),
          _sale(paid: 5000, withCustomer: true), // still owes money
          _sale(discount: 2500, paid: 17500),
          _sale(voided: true, paid: 20000),
          _sale(items: 1),
        ];
        for (final sale in variants) {
          final pdf = await buildReceiptPdf(
            sale,
            const BusinessDetails(id: 'b', name: 'Sans adresse', currency: 'GNF'),
            fonts: fonts,
          );
          expect(_latin1(pdf.sublist(0, 5)), '%PDF-');
        }
      },
    );

    test('the file is named after the sale number', () {
      expect(receiptPdfFilename(_sale()), 'recu-VTE-0042.pdf');
    });
  });

  group('Reçu en PDF button', () {
    late FakeSalesApi salesApi;
    late FakeProductsApi productsApi;

    setUp(() {
      final catalog = [
        testProduct(id: 'p1', name: 'Eau minérale 1.5L', stock: 10, salePrice: 5000),
      ];
      productsApi = FakeProductsApi(catalog);
      salesApi = FakeSalesApi(catalog: catalog, customers: const []);
    });

    Future<void> openFirstReceipt(
      WidgetTester tester, {
      List<SharedFile>? sharedFiles,
      Object? shareError,
      bool voided = false,
    }) async {
      await salesApi.checkout(
        const CheckoutRequest(
          items: [CheckoutLine(productId: 'p1', quantity: 1)],
          payments: [CheckoutPayment(method: PaymentMethod.cash, amount: 5000)],
          clientRequestId: 'seed-request-0001',
        ),
      );
      if (voided) await salesApi.voidSale('sale-1');
      await pumpAuthenticatedApp(
        tester,
        products: productsApi,
        sales: salesApi,
        sharedFiles: sharedFiles,
        fileShareError: shareError,
        receiptFonts: fonts,
      );
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historique des ventes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VTE-0001'));
      await tester.pumpAndSettle();
    }

    testWidgets('shares the receipt as a PDF file', (tester) async {
      final shared = <SharedFile>[];
      await openFirstReceipt(tester, sharedFiles: shared);

      await tester.tap(find.byTooltip('Reçu en PDF'));
      await tester.pumpAndSettle();

      final file = shared.single;
      expect(file.filename, 'recu-VTE-0001.pdf');
      expect(file.mimeType, 'application/pdf');
      expect(_latin1(file.bytes.sublist(0, 5)), '%PDF-');
      expect(file.text, contains('VTE-0001'));
      expect(file.text, contains('Boutique Demo'));
    });

    testWidgets('a voided sale can still be exported (the PDF says it is void)', (tester) async {
      final shared = <SharedFile>[];
      await openFirstReceipt(tester, sharedFiles: shared, voided: true);

      expect(find.text('VENTE ANNULÉE'), findsOneWidget);
      await tester.tap(find.byTooltip('Reçu en PDF'));
      await tester.pumpAndSettle();

      expect(shared.single.filename, 'recu-VTE-0001.pdf');
    });

    testWidgets('a failure is explained and the button works again', (tester) async {
      await openFirstReceipt(tester, shareError: Exception('share sheet unavailable'));

      await tester.tap(find.byTooltip('Reçu en PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Impossible de créer le PDF du reçu. Réessayez.'), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.picture_as_pdf_outlined),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
