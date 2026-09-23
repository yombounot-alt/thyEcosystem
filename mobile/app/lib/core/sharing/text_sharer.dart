import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

typedef TextSharer = Future<void> Function(String text);

/// Opens the system share sheet (WhatsApp, SMS, …) with plain text — receipts, debt reminders.
/// Behind a provider so tests can capture what would be shared without a platform channel.
final textSharerProvider = Provider<TextSharer>((ref) {
  return (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  };
});
