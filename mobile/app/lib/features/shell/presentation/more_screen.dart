import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_selectors.dart';
import '../../payments/application/payments_providers.dart';
import '../../sales/offline/pending_sales_repository.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  /// Sales waiting to be sent stay on the phone and go out at the next sign-in — but leaving
  /// while some are pending is worth a moment of attention.
  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final waiting = ref.read(activePendingSalesProvider).length;
    if (waiting > 0) {
      final message =
          waiting > 1
              ? '$waiting ventes ne sont pas encore sur le serveur. Elles restent gardées sur ce '
                  'téléphone et seront envoyées à votre prochaine connexion avec ce compte, dès que '
                  'le réseau est disponible.'
              : "1 vente n'est pas encore sur le serveur. Elle reste gardée sur ce téléphone et sera "
                  'envoyée à votre prochaine connexion avec ce compte, dès que le réseau est '
                  'disponible.';
      final leave = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Des ventes ne sont pas envoyées'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Rester connecté'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
      );
      if (leave != true) return;
    }
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).profile;
    final business = ref.watch(activeBusinessProvider);
    final isOwner = ref.watch(canManagePaymentMethodsProvider);
    final toVerify = ref.watch(paymentsToVerifyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Plus')),
      body: ListView(
        children: [
          if (profile != null)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(profile.fullName ?? profile.phone),
              subtitle: Text([profile.phone, if (business != null) business.name].join(' · ')),
            ),
          const Divider(),
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
                    ? Text(
                      toVerify > 1 ? '$toVerify paiements à vérifier' : '1 paiement à vérifier',
                    )
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text('Déconnexion', style: TextStyle(color: AppColors.danger)),
            onTap: () => _logout(context, ref),
          ),
        ],
      ),
    );
  }
}
