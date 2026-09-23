import '../../../core/theme/formatters.dart';

/// Polite payment reminder to send to a customer by WhatsApp/SMS.
String buildDebtReminderText({
  required String customerName,
  required String businessName,
  required double owed,
  required String currency,
  DateTime? dueDate,
}) {
  final amount = formatMoney(owed, currency: currency);
  final due = dueDate == null ? '' : ' (échéance : ${formatDay(dueDate)})';
  return 'Bonjour $customerName, petit rappel de la part de $businessName : '
      'il vous reste $amount à régler$due. Merci de votre confiance !';
}
