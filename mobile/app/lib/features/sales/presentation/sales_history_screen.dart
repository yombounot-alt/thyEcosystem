import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/sales_providers.dart';
import '../data/sale_models.dart';
import '../offline/pending_sales_repository.dart';

class SalesHistoryScreen extends ConsumerWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(salesHistoryProvider);
    final currency = ref.watch(currencyProvider);
    final pending = ref.watch(activePendingSalesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique des ventes')),
      body: Column(
        children: [
          // Sales rung up offline are not in the server's list yet, but they did happen.
          if (pending.isNotEmpty)
            ListTile(
              tileColor: AppColors.warning.withValues(alpha: 0.12),
              leading: const Icon(Icons.cloud_upload_outlined, color: AppColors.warning),
              title: Text(
                '${pending.length} vente${pending.length > 1 ? 's' : ''} en attente d\'envoi',
              ),
              subtitle: const Text('Pas encore dans cette liste ni dans le tableau de bord.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/sales/pending'),
            ),
          Expanded(
            child: AsyncView(
              value: sales,
              onRetry: () => ref.invalidate(salesHistoryProvider),
              data: (page) {
                if (page.items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'Aucune vente pour le moment.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(salesHistoryProvider);
                    await ref.read(salesHistoryProvider.future);
                  },
                  child: ListView.separated(
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _SaleTile(sale: page.items[i], currency: currency),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale, required this.currency});

  final Sale sale;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      formatDateTime(sale.soldAt),
      sale.customer?.fullName ?? 'Comptoir',
      if (sale.isOnCredit && !sale.isVoid) 'À crédit',
    ].join(' · ');

    return ListTile(
      onTap: () => context.push('/sales/${sale.id}'),
      title: Text(sale.saleNumber),
      subtitle: Text(subtitle),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatMoney(sale.total, currency: currency),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration: sale.isVoid ? TextDecoration.lineThrough : null,
            ),
          ),
          if (sale.isVoid)
            const Text('Annulée', style: TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
      ),
    );
  }
}
