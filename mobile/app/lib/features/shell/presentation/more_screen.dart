import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_selectors.dart';
import '../../auth/data/auth_models.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../payments/application/payments_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/data/team_models.dart';
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

  /// Another business of the same account: its own products, sales and team. Sales still waiting
  /// to be sent stay attached to the business they were rung up in, and are sent when it is active.
  Future<void> _switchBusiness(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(authControllerProvider).profile;
    final activeId = ref.read(activeBusinessProvider)?.id;
    if (profile == null) return;
    final chosen = await showModalBottomSheet<BusinessSummary>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Choisir une entreprise')),
                const Divider(height: 1),
                for (final b in profile.businesses)
                  ListTile(
                    leading: Icon(
                      b.id == activeId ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: b.id == activeId ? context.colors.primary : null,
                    ),
                    title: Text(b.name),
                    subtitle: Text(roleLabel(b.role)),
                    onTap: () => Navigator.pop(sheetContext, b),
                  ),
              ],
            ),
          ),
    );
    if (chosen == null || chosen.id == activeId || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).switchBusiness(chosen.id);
      if (context.mounted) context.go('/dashboard');
      messenger.showSnackBar(SnackBar(content: Text('Vous travaillez dans ${chosen.name}')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).profile;
    final canManageTeam = ref.watch(canManageTeamProvider);
    final canEditBusiness = ref.watch(canEditBusinessProvider);
    final unread = ref.watch(unreadNotificationsProvider).value ?? 0;
    final invitations = ref.watch(receivedInvitationsProvider).value ?? const [];
    final business = ref.watch(activeBusinessProvider);
    final isOwner = ref.watch(canManagePaymentMethodsProvider);
    final toVerify = ref.watch(paymentsToVerifyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Plus')),
      body: ListView(
        children: [
          if (profile != null)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: context.colors.primary,
                child: Icon(Icons.person, color: context.colors.onPrimary),
              ),
              title: Text(profile.fullName ?? profile.phone),
              subtitle: Text([profile.phone, if (business != null) business.name].join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile'),
            ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Notifications'),
            trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
            onTap: () async {
              await context.push('/notifications');
              ref.invalidate(unreadNotificationsProvider);
            },
          ),
          if (invitations.isNotEmpty)
            ListTile(
              leading: Icon(Icons.mail_outline, color: context.colors.primary),
              title: const Text('Invitations reçues'),
              subtitle: Text(
                invitations.length > 1
                    ? '${invitations.length} équipes vous invitent'
                    : '${invitations.first.businessName} vous invite',
              ),
              trailing: Badge(label: Text('${invitations.length}')),
              onTap: () => context.push('/invitations'),
            ),
          const Divider(),
          if (canManageTeam)
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Équipe'),
              subtitle: const Text('Membres, rôles et invitations'),
              onTap: () => context.push('/team'),
            ),
          if (canEditBusiness)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text("Informations de l'entreprise"),
              subtitle: const Text('Nom, adresse, téléphone (imprimés sur les reçus)'),
              onTap: () => context.push('/settings/business'),
            ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Mon offre'),
            subtitle: const Text('Limites et utilisation'),
            onTap: () => context.push('/settings/subscription'),
          ),
          if ((profile?.businesses.length ?? 0) > 1)
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text("Changer d'entreprise"),
              subtitle: business != null ? Text('Actuellement : ${business.name}') : null,
              onTap: () => _switchBusiness(context, ref),
            ),
          ListTile(
            leading: const Icon(Icons.add_business_outlined),
            title: const Text('Créer une autre entreprise'),
            onTap: () => context.push('/businesses/new'),
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
            leading: Icon(Icons.logout, color: context.colors.danger),
            title: Text('Déconnexion', style: TextStyle(color: context.colors.danger)),
            onTap: () => _logout(context, ref),
          ),
        ],
      ),
    );
  }
}
