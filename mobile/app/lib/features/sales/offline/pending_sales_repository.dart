import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, immutable, mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_selectors.dart';
import 'pending_sale.dart';

/// The sales waiting to be sent, for the signed-in user (they survive an app restart and a
/// logout: what is on the phone belongs to the person who rang it up).
class PendingSalesNotifier extends Notifier<List<PendingSale>> {
  static String _key(String userId) => 'pending_sales:v1:$userId';

  String? _userId;
  Future<void> _loaded = Future.value();
  Future<void> _writes = Future.value();

  /// Completes once what was stored has been read (start-up).
  Future<void> get loaded => _loaded;

  @override
  List<PendingSale> build() {
    final userId = ref.watch(authControllerProvider.select((s) => s.profile?.id));
    _userId = userId;
    if (userId == null) return const [];

    _loaded = _load(userId);
    return const [];
  }

  Future<void> _load(String userId) async {
    final raw = await ref.read(localStoreProvider).read(_key(userId));
    if (_userId != userId || raw == null) return; // signed out or switched account meanwhile

    try {
      final stored =
          (jsonDecode(raw) as List<dynamic>)
              .map((e) => PendingSale.fromJson(e as Map<String, dynamic>))
              .toList();
      // A sale added before the read finished (very early) must not be overwritten.
      final ids = state.map((s) => s.id).toSet();
      state = [...stored.where((s) => !ids.contains(s.id)), ...state];
    } catch (error) {
      // An unreadable queue must never take the app down; it is kept aside, not deleted.
      debugPrint('Pending sales unreadable, keeping the raw copy: $error');
      await ref.read(localStoreProvider).write('${_key(userId)}:unreadable', raw);
    }
  }

  /// Adding the same sale twice (same request id) keeps a single copy.
  Future<void> add(PendingSale sale) {
    if (state.any((s) => s.id == sale.id)) return _writes;
    return _set([...state, sale]);
  }

  Future<void> update(String id, PendingSale Function(PendingSale) change) {
    return _set([for (final s in state) s.id == id ? change(s) : s]);
  }

  Future<void> remove(String id) => _set(state.where((s) => s.id != id).toList());

  Future<void> _set(List<PendingSale> next) {
    state = next;
    final userId = _userId;
    if (userId == null) return Future.value();

    final json = jsonEncode(next.map((s) => s.toJson()).toList());
    _writes = _writes.catchError((_) {}).then((_) async {
      final store = ref.read(localStoreProvider);
      await (next.isEmpty ? store.remove(_key(userId)) : store.write(_key(userId), json));
    });
    return _writes;
  }
}

final pendingSalesProvider = NotifierProvider<PendingSalesNotifier, List<PendingSale>>(
  PendingSalesNotifier.new,
);

/// Only the sales of the business the user is working in.
final activePendingSalesProvider = Provider<List<PendingSale>>((ref) {
  final businessId = ref.watch(activeBusinessProvider)?.id;
  return [
    for (final s in ref.watch(pendingSalesProvider))
      if (s.businessId == businessId) s,
  ];
});

/// How many units of each product are sold but not yet on the server. Value-comparable, so the
/// screens that depend on it only refresh when a quantity really changes.
@immutable
class PendingStock {
  const PendingStock(this.quantities);

  final Map<String, double> quantities;

  double of(String productId) => quantities[productId] ?? 0;

  @override
  bool operator ==(Object other) =>
      other is PendingStock && mapEquals(other.quantities, quantities);

  @override
  int get hashCode =>
      Object.hashAllUnordered(quantities.entries.map((e) => Object.hash(e.key, e.value)));
}

/// Stock shown in the app is net of these, otherwise the shop could sell the same last unit twice
/// while offline.
final pendingStockProvider = Provider<PendingStock>((ref) {
  final quantities = <String, double>{};
  for (final sale in ref.watch(activePendingSalesProvider)) {
    for (final line in sale.request.items) {
      quantities[line.productId] = (quantities[line.productId] ?? 0) + line.quantity;
    }
  }
  return PendingStock(quantities);
});
