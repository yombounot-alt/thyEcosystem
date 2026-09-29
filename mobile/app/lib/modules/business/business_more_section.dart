import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/payments/application/payments_providers.dart';

/// THY Business entries of the "Plus" menu.
class BusinessMoreSection extends ConsumerWidget {
  const BusinessMoreSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(canManagePaymentMethodsProvider);
    final toVerify = ref.watch(paymentsToVerifyProvider);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: const Text('Clients'),
          onTap: () => context.push('/customers'),
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Créances'),
          onTap: () => context.push('/credits'),
        ),
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Dépenses'),
          onTap: () => context.push('/expenses'),
        ),
        ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Paiements'),
          subtitle:
              toVerify > 0
                  ? Text(toVerify > 1 ? '$toVerify paiements à vérifier' : '1 paiement à vérifier')
                  : null,
          trailing: toVerify > 0 ? Badge(label: Text('$toVerify')) : null,
          onTap: () => context.push('/payments'),
        ),
        if (isOwner)
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Moyens de paiement'),
            subtitle: const Text('Vos numéros Orange Money / Mobile Money et codes marchand'),
            onTap: () => context.push('/settings/payment-methods'),
          ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Historique des ventes'),
          onTap: () => context.push('/sales'),
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Catégories'),
          onTap: () => context.push('/categories'),
        ),
        ListTile(
          leading: const Icon(Icons.swap_vert),
          title: const Text('Mouvements de stock'),
          onTap: () => context.push('/stock/history'),
        ),
      ],
    );
  }
}
