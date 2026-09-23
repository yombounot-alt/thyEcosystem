import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/formatters.dart';
import '../../business/data/business_api.dart';
import '../data/sale_models.dart';

const _regularFontAsset = 'assets/fonts/Roboto-Regular.ttf';
const _boldFontAsset = 'assets/fonts/Roboto-Bold.ttf';

const _brand = PdfColor.fromInt(0xFF0F6E4E);
const _danger = PdfColor.fromInt(0xFFD64545);
const _success = PdfColor.fromInt(0xFF1E8E4E);

/// A PDF must embed its own font: the built-in PDF fonts cannot draw every French accent.
class ReceiptFonts {
  const ReceiptFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

Future<ReceiptFonts> loadReceiptFonts(AssetBundle bundle) async {
  final regular = await bundle.load(_regularFontAsset);
  final bold = await bundle.load(_boldFontAsset);
  return ReceiptFonts(regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
}

/// Loaded once, then reused for every receipt.
final receiptFontsProvider = FutureProvider<ReceiptFonts>((ref) => loadReceiptFonts(rootBundle));

/// File name the receipt is shared under, e.g. `recu-VTE-0001.pdf`.
String receiptPdfFilename(Sale sale) => 'recu-${sale.saleNumber}.pdf';

/// `intl` groups thousands with a narrow no-break space (U+202F); the embedded font has no glyph
/// for it. A plain no-break space looks the same and keeps "13 500 GNF" from splitting across lines.
String _pdfText(String text) => text.replaceAll(' ', ' ');

/// The receipt of [sale] as a printable / shareable PDF (A5, one or several pages).
/// [change] is the cash handed back, only known right after checkout.
Future<Uint8List> buildReceiptPdf(
  Sale sale,
  BusinessDetails business, {
  required ReceiptFonts fonts,
  double change = 0,
  bool compress = true,
}) {
  final currency = business.currency;
  String money(num amount) => _pdfText(formatMoney(amount, currency: currency));

  final document = pw.Document(
    compress: compress,
    title: 'Reçu ${sale.saleNumber}',
    author: business.name,
    creator: 'THY Business',
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );

  pw.Widget line(
    String label,
    String value, {
    bool bold = false,
    double size = 10.5,
    PdfColor? color,
  }) {
    final style = pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(_pdfText(label), style: style),
          pw.Text(_pdfText(value), style: style, softWrap: false),
        ],
      ),
    );
  }

  pw.Widget cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    PdfColor? color,
    bool wrap = true,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        _pdfText(text),
        textAlign: align,
        softWrap: wrap,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  final address = business.address;
  final phone = business.phone;
  final customer = sale.customer;

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(30),
      footer:
          (context) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _pdfText('${business.name} · ${sale.saleNumber}'),
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                if (context.pagesCount > 1)
                  pw.Text(
                    'Page ${context.pageNumber}/${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
              ],
            ),
          ),
      build:
          (context) => [
            // --- header ---------------------------------------------------------------------
            pw.Center(
              child: pw.Text(
                _pdfText(business.name),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _brand),
              ),
            ),
            if (address != null && address.isNotEmpty)
              pw.Center(
                child: pw.Text(
                  _pdfText(address),
                  style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
                ),
              ),
            if (phone != null && phone.isNotEmpty)
              pw.Center(
                child: pw.Text(
                  _pdfText(phone),
                  style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
                ),
              ),
            pw.SizedBox(height: 10),
            pw.Divider(color: _brand, thickness: 1.5),
            pw.SizedBox(height: 4),

            // --- sale info --------------------------------------------------------------------
            line('Reçu', sale.saleNumber, bold: true, size: 12),
            line('Date', formatDateTime(sale.soldAt)),
            if (customer != null) line('Client', customer.fullName),
            if (sale.isVoid)
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 8),
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _danger, width: 1.2),
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'VENTE ANNULÉE',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _danger,
                    ),
                  ),
                ),
              ),
            pw.SizedBox(height: 12),

            // --- items ------------------------------------------------------------------------
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(4.2),
                1: const pw.FixedColumnWidth(30),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(2.7),
              },
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.8),
              ),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    cell('Article', bold: true),
                    cell('Qté', bold: true, align: pw.TextAlign.center, wrap: false),
                    cell('Prix unitaire', bold: true, align: pw.TextAlign.right, wrap: false),
                    cell('Total', bold: true, align: pw.TextAlign.right, wrap: false),
                  ],
                ),
                for (final item in sale.items)
                  pw.TableRow(
                    children: [
                      cell(item.productName),
                      cell(formatQuantity(item.quantity), align: pw.TextAlign.center, wrap: false),
                      cell(money(item.unitPrice), align: pw.TextAlign.right, wrap: false),
                      cell(money(item.lineTotal), align: pw.TextAlign.right, wrap: false),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 12),

            // --- totals and payments ------------------------------------------------------------
            line('Sous-total', money(sale.subtotal)),
            if (sale.discountTotal > 0) line('Réduction', '−${money(sale.discountTotal)}'),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              child: line('TOTAL', money(sale.total), bold: true, size: 14),
            ),
            pw.SizedBox(height: 6),
            for (final payment in sale.payments)
              line(PaymentMethod.label(payment.method), money(payment.amount)),
            if (change > 0) line('Monnaie rendue', money(change), color: _success),
            if (sale.isOnCredit && !sale.isVoid)
              line('Reste à payer', money(sale.amountDue), bold: true, size: 12, color: _danger),

            pw.SizedBox(height: 22),
            pw.Center(
              child: pw.Text(
                'Merci de votre confiance !',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _brand),
              ),
            ),
          ],
    ),
  );

  return document.save();
}
