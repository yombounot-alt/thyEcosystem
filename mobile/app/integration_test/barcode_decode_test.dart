// Runs ON A DEVICE / EMULATOR (real ML Kit), not on the host:
//   flutter test integration_test/barcode_decode_test.dart -d <device id>
//
// It draws the demo products' EAN-13 barcodes and asks the same decoder the camera uses
// (mobile_scanner → ML Kit) to read them back. So it proves two things at once: the scanner
// plugin works on the device, and the barcodes of the demo data are real, valid EAN-13.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The demo catalogue (apps/api/prisma/seed.ts builds these with an EAN-13 check digit).
const demoBarcodes = {
  'Eau minérale 1.5L': '6001234000013',
  'Jus de gingembre 33cl': '6001234000020',
  'Riz local 25kg': '6001234000037',
  'Huile végétale 1L': '6001234000044',
  'Sucre en poudre 1kg': '6001234000051',
  'Savon de toilette': '6001234000068',
};

/// The first demo codes, whose check digit was wrong: a real camera rejects them.
const invalidDemoBarcode = '6001234000011';

// --- a small EAN-13 encoder, only to draw test images --------------------------------------
const _l = [
  '0001101',
  '0011001',
  '0010011',
  '0111101',
  '0100011',
  '0110001',
  '0101111',
  '0111011',
  '0110111',
  '0001011',
];
const _g = [
  '0100111',
  '0110011',
  '0011011',
  '0100001',
  '0011101',
  '0111001',
  '0000101',
  '0010001',
  '0001001',
  '0010111',
];
const _r = [
  '1110010',
  '1100110',
  '1101100',
  '1000010',
  '1011100',
  '1001110',
  '1010000',
  '1000100',
  '1001000',
  '1110100',
];
const _parity = [
  'LLLLLL',
  'LLGLGG',
  'LLGGLG',
  'LLGGGL',
  'LGLLGG',
  'LGGLLG',
  'LGGGLL',
  'LGLGLG',
  'LGLGGL',
  'LGGLGL',
];

String _bars(String code) {
  final parity = _parity[int.parse(code[0])];
  final bits = StringBuffer('101');
  for (var i = 0; i < 6; i++) {
    bits.write((parity[i] == 'L' ? _l : _g)[int.parse(code[1 + i])]);
  }
  bits.write('01010');
  for (var i = 0; i < 6; i++) {
    bits.write(_r[int.parse(code[7 + i])]);
  }
  bits.write('101');
  return bits.toString();
}

/// A white picture with the barcode in black, quiet zones included.
Future<Uint8List> _barcodePng(String code, {int module = 6}) async {
  const quiet = 12;
  final bars = _bars(code);
  final width = (bars.length + 2 * quiet) * module;
  const height = 300;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final black = ui.Paint()..color = const ui.Color(0xFF000000);
  for (var m = 0; m < bars.length; m++) {
    if (bars[m] == '1') {
      canvas.drawRect(
        ui.Rect.fromLTWH(((quiet + m) * module).toDouble(), 50, module.toDouble(), 200),
        black,
      );
    }
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MobileScannerController scanner;

  setUp(() {
    scanner = MobileScannerController(autoStart: false, formats: const [BarcodeFormat.ean13]);
  });

  tearDown(() => scanner.dispose());

  /// Runs the decoder on a picture of [code] and returns what it read.
  Future<List<String>> read(String code) async {
    final file = File('${Directory.systemTemp.path}/barcode-$code.png');
    await file.writeAsBytes(await _barcodePng(code));
    final capture = await scanner.analyzeImage(file.path, formats: const [BarcodeFormat.ean13]);
    return [
      for (final b in capture?.barcodes ?? const <Barcode>[])
        if (b.rawValue != null) b.rawValue!,
    ];
  }

  for (final entry in demoBarcodes.entries) {
    testWidgets('ML Kit reads the barcode of "${entry.key}" (${entry.value})', (tester) async {
      expect(await read(entry.value), contains(entry.value));
    });
  }

  testWidgets('a barcode with a wrong check digit is not accepted as that code', (tester) async {
    // This is why the demo codes were replaced: the camera will not read an invalid EAN-13.
    expect(await read(invalidDemoBarcode), isNot(contains(invalidDemoBarcode)));
  });
}
