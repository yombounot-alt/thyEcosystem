import 'package:intl/intl.dart';

/// GNF has no minor unit in everyday use — always displayed without decimals.
String formatMoney(num amount, {String currency = 'GNF'}) {
  final formatter = NumberFormat.decimalPattern('fr_FR');
  return '${formatter.format(amount.round())} $currency';
}

/// Whole quantities are shown without decimals ("12"), fractional ones with two ("2.50").
String formatQuantity(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(2);
}

/// The API stores the unit as a slug ("unite"); show it the way a shopkeeper would say it.
String formatUnit(String unit, [num quantity = 2]) {
  if (unit == 'unite') return quantity == 1 ? 'unité' : 'unités';
  return unit;
}

String formatDateTime(DateTime date) => DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());

/// A calendar day (due date, expense date) — deliberately not shifted to local time.
String formatDay(DateTime date) => DateFormat('dd/MM/yyyy').format(date);
