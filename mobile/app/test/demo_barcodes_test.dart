import 'package:flutter_test/flutter_test.dart';

/// EAN-13: the 13th digit makes the weighted sum (1,3,1,3…) of all 13 digits a multiple of 10.
bool isValidEan13(String code) {
  if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(code[i]) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10 == int.parse(code[12]);
}

void main() {
  // The barcodes seed.ts gives the demo products (it computes the check digit with `ean13()`).
  const seeded = [
    '6001234000013',
    '6001234000020',
    '6001234000037',
    '6001234000044',
    '6001234000051',
    '6001234000068',
  ];

  test('the demo barcodes are valid EAN-13, so a real camera can read them', () {
    for (final code in seeded) {
      expect(isValidEan13(code), isTrue, reason: code);
    }
  });

  test('the checker itself: a known real EAN-13 passes, a wrong check digit fails', () {
    expect(isValidEan13('4006381333931'), isTrue); // a well-known real product code
    expect(isValidEan13('4006381333932'), isFalse);
    expect(isValidEan13('6001234000011'), isFalse, reason: 'the first demo codes were invalid');
    expect(isValidEan13('12345'), isFalse);
  });
}
