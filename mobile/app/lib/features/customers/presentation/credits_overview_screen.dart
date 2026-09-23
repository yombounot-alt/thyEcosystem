import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/customers_providers.dart';
import '../data/customer_models.dart';

/// "Créances": every debt still owed, latest-due first, with late ones flagged.
class CreditsOverviewScreen extends ConsumerWidget {
  const CreditsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(creditsOverviewProvider);
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Créances')),
      body: AsyncView(
        value: credits,
        onRetry: () => ref.invalidate(creditsOverviewProvider),
        data: (page) {
          if (page.items.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              message: 'Aucune créance en cours.\nTous vos clients sont à jour.',
            );
          }
          final now = DateTime.now();
          final total = page.items.fold(0.0, (sum, c) => sum + c.remainingAmount);
          final lateCount = page.items.where((c) => c.isOverdue(now)).length;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(creditsOverviewProvider);
              await ref.read(creditsOverviewProvider.future);
            },
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Total dû', style: Theme.of(context).textTheme.bodySmall),
                                Text(
                                  formatMoney(total, currency: currency),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium?.copyWith(color: AppColors.danger),
                                ),
                              ],
                            ),
                          ),
                          if (lateCount > 0)
                            Text(
                              '$lateCount en retard',
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final credit in page.items)
                  _OverviewTile(credit: credit, currency: currency, now: now),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({required this.credit, required this.currency, required this.now});

  final CustomerCredit credit;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final overdue = credit.isOverdue(now);
    final due = credit.dueDate;

    return ListTile(
      onTap: () => context.push('/customers/${credit.customerId}'),
      title: Text(credit.customer?.fullName ?? 'Client'),
      subtitle: Text(
        due == null ? 'Sans échéance' : 'Échéance : ${formatDay(due)}',
        style: TextStyle(color: overdue ? AppColors.danger : null),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatMoney(credit.remainingAmount, currency: currency),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (overdue)
            const Text('En retard', style: TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
      ),
    );
  }
}
