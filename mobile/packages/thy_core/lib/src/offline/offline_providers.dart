import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_store.dart';
import 'offline_cache.dart';

final offlineCacheProvider = Provider<OfflineCache>((ref) {
  return OfflineCache(ref.watch(localStoreProvider));
});

/// Whose data the offline cache is currently holding ("userId:businessId"); null when nobody is
/// signed in. Set by the auth controller once the profile is known.
class OfflineScope extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? scope) => state = scope;
}

final offlineScopeProvider = NotifierProvider<OfflineScope, String?>(OfflineScope.new);

/// Whether the last request reached the server. Fed by the HTTP client, read by the banner and by
/// the sync of queued sales (which retries as soon as this flips back to true).
class ConnectionStatus extends Notifier<bool> {
  @override
  bool build() => true;

  void report(bool reachable) {
    if (state != reachable) state = reachable;
  }
}

final connectionStatusProvider = NotifierProvider<ConnectionStatus, bool>(ConnectionStatus.new);
