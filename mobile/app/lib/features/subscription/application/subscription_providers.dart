import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_selectors.dart';
import '../data/subscription_api.dart';

final subscriptionApiProvider = Provider<SubscriptionApi>(
  (ref) => SubscriptionApi(ref.watch(dioProvider)),
);

/// The active business's plan and usage (any member may see it; the server enforces it).
final subscriptionProvider = FutureProvider.autoDispose<SubscriptionSummary>((ref) {
  final business = ref.watch(activeBusinessProvider);
  if (business == null) throw StateError('No active business');
  return ref.watch(subscriptionApiProvider).summary(business.id);
});
