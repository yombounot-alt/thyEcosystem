import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/offline/offline_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../offline/pending_sale.dart';
import '../offline/pending_sales_repository.dart';
import '../offline/sales_sync_service.dart';
import 'pending_sale_actions.dart';

/// Every sale that is on the phone and not (yet) on the server.
class PendingSalesScreen extends ConsumerWidget {
  const PendingSalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = [...ref.watch(activePendingSalesProvider)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final syncing = ref.watch(salesSyncingProvider);
    final online = ref.watch(connectionStatusProvider);
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventes en attente'),
        actions: [
          IconButton(
            icon:
                syncing
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.sync),
            tooltip: 'Envoyer maintenant',
            onPressed: syncing ? null : () => ref.read(salesSyncServiceProvider).syncNow(),
          ),
        ],
      ),
      body:
          sales.isEmpty
              ? const EmptyState(
                icon: Icons.cloud_done_outlined,
                message: 'Toutes les ventes sont envoyées au serveur.',
              )
              : ListView.separated(
                itemCount: sales.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Text(
                        online
                            ? 'Ces ventes seront envoyées automatiquement. Le stock affiché en tient déjà compte.'
                            : 'Pas de réseau : les ventes restent en sécurité sur ce téléphone et partiront '
                                'dès le retour de la connexion. Le stock affiché en tient déjà compte.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }
                  return _PendingTile(sale: sales[i - 1], currency: currency);
                },
              ),
    );
  }
}

class _PendingTile extends ConsumerWidget {
  const _PendingTile({required this.sale, required this.currency});

  final PendingSale sale;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = sale.receipt;
    final subtitle = [
      formatDateTime(sale.createdAt),
      receipt.customer?.fullName ?? 'Comptoir',
      if (receipt.isOnCredit) 'À crédit',
    ].join(' · ');

    return Column(
      children: [
        ListTile(
          onTap: () => context.push('/sales/pending/${sale.id}'),
          title: Text(receipt.saleNumber),
          subtitle: Text(subtitle),
          trailing: Text(
            formatMoney(receipt.total, currency: currency),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Icon(
                sale.isFailed ? Icons.error_outline : Icons.schedule,
                size: 16,
                color: sale.isFailed ? AppColors.danger : AppColors.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sale.isFailed
                      ? sale.lastError ?? 'Refusée par le serveur.'
                      : "En attente d'envoi",
                  style: TextStyle(
                    fontSize: 12,
                    color: sale.isFailed ? AppColors.danger : AppColors.warning,
                  ),
                ),
              ),
              if (sale.isFailed) ...[
                TextButton(
                  onPressed: () => ref.read(salesSyncServiceProvider).retry(sale.id),
                  child: const Text('Réessayer'),
                ),
                TextButton(
                  onPressed: () => confirmDeletePendingSale(context, ref, sale),
                  child: const Text('Supprimer'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
