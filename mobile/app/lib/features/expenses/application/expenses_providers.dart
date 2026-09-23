import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../data/expense_models.dart';
import '../data/expenses_api.dart';

final expensesApiProvider = Provider<ExpensesApi>((ref) {
  return ExpensesApi(ref.watch(dioProvider));
});

enum ExpensePeriod {
  today('Aujourd\'hui'),
  week('7 jours'),
  month('Ce mois'),
  all('Tout');

  const ExpensePeriod(this.label);

  final String label;

  /// Inclusive calendar-day range; null bounds mean "no limit".
  ({DateTime? from, DateTime? to}) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case ExpensePeriod.today:
        return (from: today, to: today);
      case ExpensePeriod.week:
        return (from: today.subtract(const Duration(days: 6)), to: today);
      case ExpensePeriod.month:
        return (from: DateTime(now.year, now.month), to: today);
      case ExpensePeriod.all:
        return (from: null, to: null);
    }
  }
}

final expensesProvider = FutureProvider.autoDispose.family<ExpensePage, ExpensePeriod>((
  ref,
  period,
) {
  final range = period.range(DateTime.now());
  return ref.watch(expensesApiProvider).list(from: range.from, to: range.to);
});

final expenseProvider = FutureProvider.autoDispose.family<Expense, String>((ref, id) {
  return ref.watch(expensesApiProvider).get(id);
});

/// Expenses feed the dashboard's profit, so refresh both together.
void invalidateExpenseData(WidgetRef ref, {String? expenseId}) {
  ref.invalidate(expensesProvider);
  if (expenseId != null) ref.invalidate(expenseProvider(expenseId));
  invalidateDashboard(ref);
}
