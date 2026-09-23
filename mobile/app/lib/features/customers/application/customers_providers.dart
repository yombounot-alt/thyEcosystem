import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/paginated.dart';
import '../../../core/providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../data/customer_models.dart';
import '../data/customers_api.dart';

final customersApiProvider = Provider<CustomersApi>((ref) {
  return CustomersApi(ref.watch(dioProvider));
});

/// Customers matching [search] (empty = all, first page).
final customersListProvider = FutureProvider.autoDispose.family<List<Customer>, String>((
  ref,
  search,
) async {
  final page = await ref.watch(customersApiProvider).list(search: search);
  return page.items;
});

final customerProvider = FutureProvider.autoDispose.family<Customer, String>((ref, id) {
  return ref.watch(customersApiProvider).get(id);
});

final customerCreditsProvider = FutureProvider.autoDispose.family<List<CustomerCredit>, String>((
  ref,
  customerId,
) {
  return ref.watch(customersApiProvider).credits(customerId);
});

final customerStatementProvider = FutureProvider.autoDispose.family<List<StatementEntry>, String>((
  ref,
  customerId,
) {
  return ref.watch(customersApiProvider).statement(customerId);
});

/// All debts still owed, across customers ("Créances").
final creditsOverviewProvider = FutureProvider.autoDispose<Paginated<CustomerCredit>>((ref) {
  return ref.watch(customersApiProvider).outstandingCredits();
});

/// Anything that changes what a customer owes must refresh these.
void invalidateCustomerData(WidgetRef ref, {String? customerId}) {
  ref.invalidate(customersListProvider);
  ref.invalidate(creditsOverviewProvider);
  invalidateDashboard(ref);
  if (customerId != null) {
    ref.invalidate(customerProvider(customerId));
    ref.invalidate(customerCreditsProvider(customerId));
    ref.invalidate(customerStatementProvider(customerId));
  }
}
