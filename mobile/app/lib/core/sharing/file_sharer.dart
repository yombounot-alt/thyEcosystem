import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

typedef FileSharer =
    Future<void> Function({
      required Uint8List bytes,
      required String filename,
      required String mimeType,
      String? text,
    });

/// Opens the system share sheet with a file (PDF receipts → WhatsApp, e-mail, "save to files"…).
/// In a browser without the Web Share API the file is downloaded instead.
/// Behind a provider so tests can capture what would be shared without a platform channel.
final fileSharerProvider = Provider<FileSharer>((ref) {
  return ({required bytes, required filename, required mimeType, text}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
        fileNameOverrides: [filename],
        text: text,
      ),
    );
  };
});
