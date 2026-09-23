import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_selectors.dart';
import '../data/business_api.dart';

final businessApiProvider = Provider<BusinessApi>((ref) => BusinessApi(ref.watch(dioProvider)));

/// Name, address and phone for receipts.
final businessDetailsProvider = FutureProvider.autoDispose<BusinessDetails>((ref) {
  final business = ref.watch(activeBusinessProvider);
  if (business == null) throw StateError('No active business');
  return ref.watch(businessApiProvider).details(business.id);
});
