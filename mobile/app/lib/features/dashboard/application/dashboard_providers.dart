import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/dashboard_api.dart';
import '../data/dashboard_models.dart';

final dashboardApiProvider = Provider<DashboardApi>((ref) {
  return DashboardApi(ref.watch(dioProvider));
});

final dashboardSummaryProvider = FutureProvider.autoDispose
    .family<DashboardSummary, DashboardPeriod>(
      (ref, period) => ref.watch(dashboardApiProvider).summary(period),
    );

final salesChartProvider = FutureProvider.autoDispose<List<SalesChartPoint>>((ref) {
  return ref.watch(dashboardApiProvider).salesChart();
});

final topProductsProvider = FutureProvider.autoDispose.family<List<TopProduct>, DashboardPeriod>(
  (ref, period) => ref.watch(dashboardApiProvider).topProducts(period),
);

/// The dashboard is derived from sales, expenses, stock and credits: refresh it after any of them changes
/// while the Accueil screen may still be mounted underneath (e.g. an alert opened a customer).
void invalidateDashboard(WidgetRef ref) {
  ref.invalidate(dashboardSummaryProvider);
  ref.invalidate(salesChartProvider);
  ref.invalidate(topProductsProvider);
}
