import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_selectors.dart';
import '../../auth/application/auth_state.dart';
import '../../business/application/business_providers.dart';
import '../../categories/application/categories_providers.dart';
import '../../customers/application/customers_providers.dart';
import '../../products/application/products_providers.dart';

/// Right after signing in, quietly reads what the till needs (the shop's details for receipts, the
/// catalogue, the customers to sell on credit) so the shop can carry on offline from the very first
/// day — not only for screens somebody happened to open while online.
///
/// Failures are ignored: it is a head start, never a requirement. Read once, from the app root.
final offlineWarmupProvider = Provider<void>((ref) {
  ref.listen(authControllerProvider.select((s) => s.status), (previous, status) {
    if (status == AuthStatus.authenticated) unawaited(_warmUp(ref));
  }, fireImmediately: true);
});

Future<void> _warmUp(Ref ref) async {
  Future<void> quietly(Future<Object?> read) => read.then<void>((_) {}, onError: (_) {});

  final business = ref.read(activeBusinessProvider);
  await Future.wait([
    if (business != null) quietly(ref.read(businessApiProvider).details(business.id)),
    quietly(ref.read(categoriesApiProvider).list()),
    quietly(ref.read(productsApiProvider).list()),
    quietly(ref.read(customersApiProvider).list()),
  ]);
}
