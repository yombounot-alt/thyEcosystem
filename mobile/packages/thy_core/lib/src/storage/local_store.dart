import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny key → string store that survives app restarts (the offline cache, the queue of sales
/// waiting to be synced). Behind an interface so tests use memory and a bigger engine (SQLite)
/// can replace it later without touching the features that use it.
abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Backed by SharedPreferences (SharedPreferences on Android/iOS, localStorage in a browser).
class SharedPrefsLocalStore implements LocalStore {
  SharedPrefsLocalStore() : _prefs = SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await _prefs).setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _prefs).remove(key);
  }
}

class MemoryLocalStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

final localStoreProvider = Provider<LocalStore>((ref) => SharedPrefsLocalStore());
