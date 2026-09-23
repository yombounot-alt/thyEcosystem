import '../../../core/theme/formatters.dart';
import '../../business/data/business_api.dart';
import '../data/sale_models.dart';

/// Plain-text receipt, sized for messaging apps (WhatsApp/SMS) and thermal-printer-like widths.
String buildReceiptText(Sale sale, BusinessDetails business, {double change = 0}) {
  final currency = business.currency;
  final buffer = StringBuffer()..writeln(business.name);

  final address = business.address;
  if (address != null && address.isNotEmpty) buffer.writeln(address);
  final phone = business.phone;
  if (phone != null && phone.isNotEmpty) buffer.writeln(phone);

  buffer
    ..writeln()
    ..writeln('Reçu ${sale.saleNumber}')
    ..writeln(formatDateTime(sale.soldAt));

  if (sale.customer != null) buffer.writeln('Client : ${sale.customer!.fullName}');
  if (sale.isVoid) buffer.writeln('*** VENTE ANNULÉE ***');

  buffer.writeln('--------------------------------');
  for (final item in sale.items) {
    buffer
      ..writeln(item.productName)
      ..writeln(
        '  ${formatQuantity(item.quantity)} x ${formatMoney(item.unitPrice, currency: currency)}'
        ' = ${formatMoney(item.lineTotal, currency: currency)}',
      );
  }
  buffer.writeln('--------------------------------');

  buffer.writeln('Sous-total : ${formatMoney(sale.subtotal, currency: currency)}');
  if (sale.discountTotal > 0) {
    buffer.writeln('Réduction : -${formatMoney(sale.discountTotal, currency: currency)}');
  }
  buffer.writeln('TOTAL : ${formatMoney(sale.total, currency: currency)}');

  for (final payment in sale.payments) {
    buffer.writeln(
      '${PaymentMethod.label(payment.method)} : ${formatMoney(payment.amount, currency: currency)}',
    );
  }
  if (change > 0) {
    buffer.writeln('Monnaie rendue : ${formatMoney(change, currency: currency)}');
  }
  if (sale.isOnCredit && !sale.isVoid) {
    buffer.writeln('Reste à payer : ${formatMoney(sale.amountDue, currency: currency)}');
  }

  buffer
    ..writeln()
    ..writeln('Merci de votre confiance !');
  return buffer.toString().trimRight();
}
