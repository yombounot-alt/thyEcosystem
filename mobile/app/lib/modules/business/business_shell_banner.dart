import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';

import '../../features/payments/application/payments_providers.dart';

/// Payments customers declared and that are waiting for the owner's check (only those who may
/// verify see it): shown above the tabs on every main screen.
class BusinessShellBanner extends ConsumerWidget {
  const BusinessShellBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(paymentsToVerifyProvider);
    if (count == 0) return const SizedBox.shrink();
    return Material(
      color: context.colors.primaryContainer,
      child: InkWell(
        onTap: () => context.push('/payments?status=submitted'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.hourglass_top, size: 20, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count > 1 ? '$count paiements à vérifier' : '1 paiement à vérifier',
                  style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.onSurface),
                ),
              ),
              Icon(Icons.chevron_right, color: context.colors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}
