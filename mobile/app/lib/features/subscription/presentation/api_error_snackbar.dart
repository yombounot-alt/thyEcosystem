import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_core/thy_core.dart';

import '../data/subscription_api.dart';

/// Shows the server's message. When the refusal comes from the plan's limits, it also offers to
/// open "Mon offre", so the user sees what is used and what the plan allows.
void showApiError(BuildContext context, ApiException error) {
  final router = GoRouter.maybeOf(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.message),
      action:
          error.code == entitlementLimitReached && router != null
              ? SnackBarAction(
                label: 'Voir mon offre',
                onPressed: () => router.push('/settings/subscription'),
              )
              : null,
    ),
  );
}
