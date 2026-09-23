import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/expenses_providers.dart';
import '../data/expense_models.dart';

IconData expenseIcon(String category) {
  switch (category) {
    case 'transport':
      return Icons.local_shipping_outlined;
    case 'loyer':
      return Icons.home_work_outlined;
    case 'salaire':
      return Icons.groups_outlined;
    case 'electricite':
      return Icons.bolt_outlined;
    case 'internet':
      return Icons.wifi;
    case 'achat':
      return Icons.shopping_bag_outlined;
    case 'maintenance':
      return Icons.build_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen> {
  ExpensePeriod _period = ExpensePeriod.month;

  Future<void> _delete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Supprimer cette dépense ?'),
            content: Text(
              '${ExpenseCategory.label(expense.category)} — '
              '${formatMoney(expense.amount, currency: ref.read(currencyProvider))}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(expensesApiProvider).delete(expense.id);
      invalidateExpenseData(ref);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(expensesProvider(_period));
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/new'),
        icon: const Icon(Icons.add),
        label: const Text('Dépense'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final period in ExpensePeriod.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(period.label),
                      selected: _period == period,
                      onSelected: (_) => setState(() => _period = period),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: expenses,
              onRetry: () => ref.invalidate(expensesProvider),
              data: (page) {
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(expensesProvider);
                    await ref.read(expensesProvider(_period).future);
                  },
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Total — ${_period.label.toLowerCase()}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                Text(
                                  formatMoney(page.totalAmount, currency: currency),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (page.items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: EmptyState(
                            icon: Icons.receipt_long_outlined,
                            message: 'Aucune dépense sur cette période.',
                          ),
                        ),
                      for (final expense in page.items)
                        ListTile(
                          onTap: () => context.push('/expenses/${expense.id}/edit'),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            child: Icon(expenseIcon(expense.category), color: AppColors.primary),
                          ),
                          title: Text(ExpenseCategory.label(expense.category)),
                          subtitle: Text(
                            [
                              formatDay(expense.expenseDate),
                              if (expense.description != null && expense.description!.isNotEmpty)
                                expense.description!,
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatMoney(expense.amount, currency: currency),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    context.push('/expenses/${expense.id}/edit');
                                  }
                                  if (action == 'delete') _delete(expense);
                                },
                                itemBuilder:
                                    (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Modifier')),
                                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                                    ],
                              ),
                            ],
                          ),
                        ),
                    ],
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
