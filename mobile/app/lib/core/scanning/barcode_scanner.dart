import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'barcode_scan_screen.dart';
import 'scan_types.dart';

export 'scan_types.dart';

/// Opens the camera scanner. With [continuous] it stays open and reports every code (ringing up
/// several articles in a row); otherwise it closes after the first one (filling a form field).
typedef BarcodeScanner =
    Future<void> Function(
      BuildContext context, {
      required ScanHandler onCode,
      bool continuous,
      String title,
    });

/// The real thing: a full-screen camera. Behind a provider so tests can feed codes without a camera.
final barcodeScannerProvider = Provider<BarcodeScanner>((ref) {
  return (
    context, {
    required onCode,
    bool continuous = false,
    String title = 'Scanner un code-barres',
  }) {
    // Root navigator: the caller sits inside the tab shell, and the scanner must cover the tab bar.
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BarcodeScanScreen(onCode: onCode, continuous: continuous, title: title),
      ),
    );
  };
});

/// Camera scanning is for phones and tablets; a browser (the desktop preview) types codes with a
/// keyboard scanner instead.
final cameraScanningAvailableProvider = Provider<bool>((ref) => !kIsWeb);
