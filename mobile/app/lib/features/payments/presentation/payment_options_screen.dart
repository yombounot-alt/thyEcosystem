import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_view.dart';
import '../application/payments_providers.dart';
import '../data/payment_method_models.dart';
import 'payment_visuals.dart';

/// Paramètres → Moyens de paiement: the numbers and codes customers can pay, all typed by the
/// owner. Nothing is preconfigured — an empty list means the owner has not filled them in yet.
class PaymentOptionsScreen extends ConsumerWidget {
  const PaymentOptionsScreen({super.key});

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    PaymentOption option,
    bool active,
  ) async {
    try {
      await ref.read(paymentMethodsApiProvider).setActive(option.id, active);
      ref.invalidate(paymentOptionsProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(canManagePaymentMethodsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Moyens de paiement')),
      floatingActionButton:
          owner
              ? FloatingActionButton.extended(
                onPressed: () => context.push('/settings/payment-methods/new'),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              )
              : null,
      body:
          !owner
              ? const EmptyState(
                icon: Icons.lock_outline,
                message: 'Seul le propriétaire du commerce peut modifier les moyens de paiement.',
              )
              : AsyncView(
                value: ref.watch(paymentOptionsProvider),
                onRetry: () => ref.invalidate(paymentOptionsProvider),
                data: (options) {
                  if (options.isEmpty) return const _NothingYet();
                  return RefreshIndicator(
                    onRefresh: () async => ref.refresh(paymentOptionsProvider.future),
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 96),
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'Vos clients voient les moyens activés quand ils paient. Vous pouvez '
                            'ajouter plusieurs numéros pour un même opérateur.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                        for (final option in options)
                          ListTile(
                            leading: PaymentOptionLogo(
                              optionId: option.id,
                              provider: option.provider,
                              hasLogo: option.hasLogo,
                            ),
                            title: Text(option.displayName),
                            subtitle: Text(
                              [
                                if (option.accountName != null) option.accountName!,
                                if (option.destination != null) option.destination!,
                                if (!option.isActive) 'désactivé',
                              ].join(' · '),
                            ),
                            trailing: Switch(
                              value: option.isActive,
                              onChanged: (value) => _toggle(context, ref, option, value),
                            ),
                            onTap: () => context.push('/settings/payment-methods/${option.id}'),
                          ),
                      ],
                    ),
                  );
                },
              ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 56, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Aucun moyen de paiement',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajoutez votre numéro Orange Money, votre numéro Mobile Money ou votre code '
              'marchand : vos clients pourront vous payer directement, et vous vérifiez chaque '
              'paiement avant de le valider.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.push('/settings/payment-methods/new'),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un moyen de paiement'),
            ),
          ],
        ),
      ),
    );
  }
}
