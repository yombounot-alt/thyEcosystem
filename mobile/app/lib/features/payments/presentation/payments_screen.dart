import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../application/payments_providers.dart';
import '../data/payment_models.dart';
import 'payment_visuals.dart';

const _filters = <(String?, String)>[
  (null, 'Tous'),
  (PaymentStatus.submitted, 'À vérifier'),
  (PaymentStatus.pending, 'En attente'),
  (PaymentStatus.verified, 'Payés'),
  (PaymentStatus.rejected, 'Refusés'),
  (PaymentStatus.cancelled, 'Annulés'),
];

/// Paiements: everything customers declared or paid directly, with the ones waiting for the
/// owner's check first in mind ("À vérifier").
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key, this.initialStatus});

  final String? initialStatus;

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  late String? _status = widget.initialStatus;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(paymentsListProvider(_status));

    return Scaffold(
      appBar: AppBar(title: const Text('Paiements')),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final (status, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _status == status,
                      onSelected: (_) => setState(() => _status = status),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: list,
              onRetry: () => ref.invalidate(paymentsListProvider(_status)),
              data: (page) {
                if (page.items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.payments_outlined,
                    message: 'Aucun paiement.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(paymentSummaryProvider);
                    ref.invalidate(paymentsListProvider(_status));
                    await ref.read(paymentsListProvider(_status).future);
                  },
                  child: ListView.separated(
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _PaymentTile(payment: page.items[index]),
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

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final ManualPayment payment;

  @override
  Widget build(BuildContext context) {
    final d = payment.declaration;
    final details = [
      if (d?.transactionReference != null) 'Réf. ${d!.transactionReference}',
      if (d?.payerName != null) d!.payerName!,
      formatDateTime(payment.createdAt),
    ].join(' · ');

    return ListTile(
      leading: PaymentOptionLogo(
        optionId: payment.method.id,
        provider: payment.method.provider,
        hasLogo: payment.method.hasLogo,
        size: 42,
      ),
      title: Text(
        '${formatMoney(payment.amount, currency: payment.currency)} · ${payment.method.displayName}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details),
      trailing: PaymentStatusBadge(status: payment.status),
      onTap: () => context.push('/payments/${payment.id}'),
    );
  }
}
