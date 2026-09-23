import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/offline/offline_providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../customers/application/customers_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../products/application/products_providers.dart';
import '../application/sales_providers.dart';
import 'pending_sale.dart';
import 'pending_sales_repository.dart';

/// True while queued sales are being sent (the banner shows a spinner).
class SalesSyncing extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final salesSyncingProvider = NotifierProvider<SalesSyncing, bool>(SalesSyncing.new);

/// Which real sale each queued sale became ("HL-3F9A21" → the server's sale), so a provisional
/// receipt that is still open can move on to the real one.
class SyncedSales extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void record(String pendingId, String saleId) => state = {...state, pendingId: saleId};
}

final syncedSalesProvider = NotifierProvider<SyncedSales, Map<String, String>>(SyncedSales.new);

/// Sends the queued sales, oldest first.
///
/// The same request id goes out on every attempt, so a sale the server already recorded (its
/// answer got lost on the way) is simply recognised — never sold twice.
class SalesSyncService {
  SalesSyncService(this._ref);

  final Ref _ref;
  Future<int>? _running;

  /// Returns how many sales were sent. Calls made while a run is in progress join it.
  Future<int> syncNow() => _running ??= _run().whenComplete(() => _running = null);

  /// Errors that say nothing about the sale itself: the server (or the session) is not ready.
  static bool _isTemporary(ApiException e) {
    final status = e.statusCode;
    return e.isConnectionProblem ||
        status == null ||
        status >= 500 ||
        status == 401 ||
        status == 408 ||
        status == 429;
  }

  Future<int> _run() async {
    final repository = _ref.read(pendingSalesProvider.notifier);
    await repository.loaded;

    final queue =
        _ref.read(activePendingSalesProvider).where((s) => !s.isFailed).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (queue.isEmpty) return 0;

    _ref.read(salesSyncingProvider.notifier).set(true);
    var sent = 0;
    try {
      for (final sale in queue) {
        try {
          final recorded = await _ref.read(salesApiProvider).checkout(sale.requestToSend);
          await repository.remove(sale.id);
          _ref.read(syncedSalesProvider.notifier).record(sale.id, recorded.id);
          sent++;
        } on ApiException catch (e) {
          if (e.isConnectionProblem) break; // still no network: nothing to record, try later
          if (_isTemporary(e)) {
            await repository.update(
              sale.id,
              (s) => s.copyWith(attempts: s.attempts + 1, lastError: e.message),
            );
            break;
          }
          // The server looked at this sale and refused it for good: keep it, say why, and move
          // on so one bad sale never blocks the ones behind it.
          await repository.update(
            sale.id,
            (s) => s.copyWith(
              status: PendingSaleStatus.failed,
              attempts: s.attempts + 1,
              lastError: e.message,
            ),
          );
        }
      }
    } finally {
      _ref.read(salesSyncingProvider.notifier).set(false);
    }

    if (sent > 0) _refreshAfterSync();
    return sent;
  }

  /// Stock, sales, customers' debts and the dashboard all just changed on the server.
  void _refreshAfterSync() {
    _ref
      ..invalidate(productsListProvider)
      ..invalidate(productProvider)
      ..invalidate(salesHistoryProvider)
      ..invalidate(stockMovementsProvider)
      ..invalidate(customersListProvider)
      ..invalidate(customerProvider)
      ..invalidate(customerCreditsProvider)
      ..invalidate(customerStatementProvider)
      ..invalidate(creditsOverviewProvider)
      ..invalidate(dashboardSummaryProvider)
      ..invalidate(salesChartProvider)
      ..invalidate(topProductsProvider);
  }

  /// Puts a failed sale back in the queue (after the cause was fixed) and tries again.
  Future<void> retry(String id) async {
    await _ref
        .read(pendingSalesProvider.notifier)
        .update(id, (s) => s.copyWith(status: PendingSaleStatus.waiting, clearError: true));
    await syncNow();
  }
}

final salesSyncServiceProvider = Provider<SalesSyncService>((ref) => SalesSyncService(ref));

/// How often the app checks whether the network is back while sales are waiting (or it is
/// offline). Null turns the timer off (tests).
final syncIntervalProvider = Provider<Duration?>((ref) => const Duration(seconds: 30));

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Decides *when* to send: as soon as the server answers again, every [syncIntervalProvider]
/// while something waits, when the app comes back to the foreground, and right after signing in.
/// Read once, from the app root.
final salesSyncCoordinatorProvider = Provider<void>((ref) {
  final service = ref.watch(salesSyncServiceProvider);

  void trySend() => unawaited(service.syncNow());

  ref.listen<bool>(connectionStatusProvider, (previous, reachable) {
    if (reachable && previous == false) trySend();
  });

  ref.listen(authControllerProvider.select((s) => s.status), (previous, status) {
    if (status == AuthStatus.authenticated) trySend();
  });

  final interval = ref.watch(syncIntervalProvider);
  if (interval != null) {
    final timer = Timer.periodic(interval, (_) {
      if (ref.read(activePendingSalesProvider).any((s) => !s.isFailed)) {
        trySend();
      } else if (!ref.read(connectionStatusProvider) &&
          ref.read(authControllerProvider).status == AuthStatus.authenticated) {
        // Nothing to send, but the banner says "offline": ask the server whether that is over.
        unawaited(ref.read(authApiProvider).me().then<void>((_) {}, onError: (_) {}));
      }
    });
    ref.onDispose(timer.cancel);
  }

  final observer = _ResumeObserver(trySend);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});
