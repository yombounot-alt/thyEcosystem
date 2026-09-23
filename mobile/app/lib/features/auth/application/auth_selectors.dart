import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_models.dart';
import 'auth_controller.dart';

/// The business the current session token is scoped to (null while signed out).
final activeBusinessProvider = Provider<BusinessSummary?>((ref) {
  final profile = ref.watch(authControllerProvider).profile;
  if (profile == null || profile.businesses.isEmpty) return null;
  return profile.businesses.firstWhere(
    (b) => b.id == profile.activeBusinessId,
    orElse: () => profile.businesses.first,
  );
});

final currencyProvider = Provider<String>((ref) {
  return ref.watch(activeBusinessProvider)?.currency ?? 'GNF';
});
