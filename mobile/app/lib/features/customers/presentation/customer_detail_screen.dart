import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sharing/text_sharer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../../sales/data/sale_models.dart';
import '../application/customers_providers.dart';
import '../application/reminder_text.dart';
import '../data/customer_models.dart';
import 'credit_dialogs.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  Future<void> _run(BuildContext context, Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref, Customer customer) async {
    final entry = await showRecordPaymentDialog(
      context,
      owed: customer.currentBalance,
      currency: ref.read(currencyProvider),
    );
    if (entry == null || !context.mounted) return;
    await _run(context, () async {
      await ref
          .read(customersApiProvider)
          .recordPayment(customer.id, amount: entry.amount, method: entry.method, note: entry.note);
      invalidateCustomerData(ref, customerId: customer.id);
    }, success: 'Paiement enregistré.');
  }

  Future<void> _grantCredit(BuildContext context, WidgetRef ref, Customer customer) async {
    final entry = await showGrantCreditDialog(context, currency: ref.read(currencyProvider));
    if (entry == null || !context.mounted) return;
    await _run(context, () async {
      await ref
          .read(customersApiProvider)
          .grantCredit(customer.id, amount: entry.amount, dueDate: entry.dueDate, note: entry.note);
      invalidateCustomerData(ref, customerId: customer.id);
    }, success: 'Dette ajoutée.');
  }

  Future<void> _sendReminder(WidgetRef ref, Customer customer, List<CustomerCredit> credits) {
    final dueDates = [
      for (final credit in credits)
        if (credit.isOutstanding && credit.dueDate != null) credit.dueDate!,
    ]..sort();

    return ref.read(textSharerProvider)(
      buildDebtReminderText(
        customerName: customer.fullName,
        businessName: ref.read(activeBusinessProvider)?.name ?? 'votre commerçant',
        owed: customer.currentBalance,
        currency: ref.read(currencyProvider),
        dueDate: dueDates.isEmpty ? null : dueDates.first,
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Customer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Supprimer ${customer.fullName} ?'),
            content: const Text(
              'Possible uniquement si le client n\'a ni vente ni dette enregistrée.',
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
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(customersApiProvider).delete(customer.id);
      invalidateCustomerData(ref);
      if (context.mounted) context.pop();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider(customerId));
    final credits = ref.watch(customerCreditsProvider(customerId));
    final statement = ref.watch(customerStatementProvider(customerId));
    final currency = ref.watch(currencyProvider);
    final loaded = customer.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(loaded?.fullName ?? 'Client'),
        actions: [
          if (loaded != null)
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') context.push('/customers/$customerId/edit');
                if (action == 'delete') _delete(context, ref, loaded);
              },
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Modifier')),
                    PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                  ],
            ),
        ],
      ),
      body: AsyncView(
        value: customer,
        onRetry: () => ref.invalidate(customerProvider(customerId)),
        data:
            (c) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderCard(customer: c, currency: currency),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: c.hasDebt ? () => _recordPayment(context, ref, c) : null,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Enregistrer un paiement'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _grantCredit(context, ref, c),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une dette'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          c.hasDebt ? () => _sendReminder(ref, c, credits.value ?? const []) : null,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Envoyer un rappel'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Dettes en cours', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                AsyncView(
                  value: credits,
                  onRetry: () => ref.invalidate(customerCreditsProvider(customerId)),
                  data: (items) {
                    final owed = items.where((credit) => credit.isOutstanding).toList();
                    if (owed.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aucune dette en cours.'),
                      );
                    }
                    return Column(
                      children: [
                        for (final credit in owed) _CreditTile(credit: credit, currency: currency),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text('Historique', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                AsyncView(
                  value: statement,
                  onRetry: () => ref.invalidate(customerStatementProvider(customerId)),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aucun mouvement.'),
                      );
                    }
                    return Column(
                      children: [
                        for (final entry in entries.reversed)
                          _StatementTile(entry: entry, currency: currency),
                      ],
                    );
                  },
                ),
              ],
            ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.customer, required this.currency});

  final Customer customer;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final contact = [
      if (customer.phone != null) customer.phone!,
      if (customer.address != null) customer.address!,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (contact.isNotEmpty) Text(contact.join(' · '), style: textTheme.bodySmall),
            if (customer.notes != null && customer.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(customer.notes!, style: textTheme.bodySmall),
              ),
            const SizedBox(height: 12),
            Text('Dette en cours', style: textTheme.bodySmall),
            const SizedBox(height: 4),
            customer.hasDebt
                ? Text(
                  formatMoney(customer.currentBalance, currency: currency),
                  style: textTheme.headlineMedium?.copyWith(color: AppColors.danger),
                )
                : Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success),
                    const SizedBox(width: 8),
                    Text('À jour', style: textTheme.titleLarge?.copyWith(color: AppColors.success)),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.credit, required this.currency});

  final CustomerCredit credit;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final overdue = credit.isOverdue(DateTime.now());
    final due = credit.dueDate;
    final subtitle = [
      due == null ? 'Sans échéance' : 'Échéance : ${formatDay(due)}',
      if (credit.note != null && credit.note!.isNotEmpty) credit.note!,
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Reste ${formatMoney(credit.remainingAmount, currency: currency)}'
        '${credit.remainingAmount < credit.originalAmount ? ' sur ${formatMoney(credit.originalAmount, currency: currency)}' : ''}',
      ),
      subtitle: Text(subtitle),
      trailing:
          overdue
              ? const Chip(
                label: Text('En retard'),
                backgroundColor: Color(0x1AD64545),
                labelStyle: TextStyle(color: AppColors.danger),
                side: BorderSide.none,
              )
              : null,
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.entry, required this.currency});

  final StatementEntry entry;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final isPayment = entry.isPayment;
    final color = isPayment ? AppColors.success : AppColors.danger;
    final title =
        isPayment
            ? 'Paiement reçu${entry.method == null ? '' : ' (${PaymentMethod.label(entry.method!)})'}'
            : 'Dette';
    final note = entry.note;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(isPayment ? Icons.arrow_downward : Icons.arrow_upward, color: color),
      ),
      title: Text(title),
      subtitle: Text(
        [formatDateTime(entry.date), if (note != null && note.isNotEmpty) note].join(' · '),
      ),
      trailing: Text(
        '${isPayment ? '−' : '+'}${formatMoney(entry.amount, currency: currency)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
