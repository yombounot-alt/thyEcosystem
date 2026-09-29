/// Prisma serializes Decimal columns as JSON strings ("5000"), other numbers as numbers.
double parseDecimal(Object? value) {
  if (value is num) return value.toDouble();
  return double.parse(value! as String);
}

double? parseDecimalOrNull(Object? value) => value == null ? null : parseDecimal(value);

/// Parses user input such as "12 500,50" (spaces and comma decimal separator allowed).
double? parseUserNumber(String input) {
  final cleaned = input.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}
