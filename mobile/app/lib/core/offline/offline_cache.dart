import 'dart:async';
import 'dart:convert';

import '../storage/local_store.dart';

class CachedEntry {
  const CachedEntry({required this.data, required this.savedAt});

  /// The decoded JSON exactly as the server sent it (a Map or a List).
  final Object? data;
  final DateTime savedAt;
}

/// The last good answer of read-only requests, so the app still has something to show with no
/// network. Bounded (least-recently-written entries are dropped) and always tied to a [scope]
/// (user + business) so one account never sees another account's data.
class OfflineCache {
  OfflineCache(this._store, {this.maxEntries = 80, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  static const _indexKey = 'offline_cache:index';
  static const _entryPrefix = 'offline_cache:entry:';

  final LocalStore _store;
  final int maxEntries;
  final DateTime Function() _now;

  /// Writes read-modify-write the index, so they run one after the other.
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  static String _fullKey(String scope, String key) => '$scope|$key';

  Future<void> put(String scope, String key, Object? data) {
    return _serial(() async {
      final full = _fullKey(scope, key);
      await _store.write(
        '$_entryPrefix$full',
        jsonEncode({'t': _now().toUtc().toIso8601String(), 'd': data}),
      );

      final index =
          await _readIndex()
            ..remove(full)
            ..insert(0, full);
      while (index.length > maxEntries) {
        await _store.remove('$_entryPrefix${index.removeLast()}');
      }
      await _store.write(_indexKey, jsonEncode(index));
    });
  }

  Future<CachedEntry?> get(String scope, String key) async {
    final raw = await _store.read('$_entryPrefix${_fullKey(scope, key)}');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CachedEntry(data: decoded['d'], savedAt: DateTime.parse(decoded['t'] as String));
    } catch (_) {
      return null; // a damaged entry is the same as no entry
    }
  }

  /// Forgets everything (logout).
  Future<void> clear() {
    return _serial(() async {
      for (final full in await _readIndex()) {
        await _store.remove('$_entryPrefix$full');
      }
      await _store.remove(_indexKey);
    });
  }

  Future<List<String>> _readIndex() async {
    final raw = await _store.read(_indexKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toList();
    } catch (_) {
      return [];
    }
  }
}
