import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sharing/text_sharer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_selectors.dart';
import '../../products/application/products_providers.dart';
import '../../sales/application/sales_providers.dart';
import '../application/payments_providers.dart';
import '../data/payment_models.dart';
import 'payment_visuals.dart';

/// Reasons the owner can pick when refusing a payment (they can also type their own).
const rejectionReasons = [
  'Transaction introuvable',
  'Montant incorrect',
  'Référence invalide',
  'Preuve insuffisante',
  'Transaction déjà utilisée',
];

/// One payment: what was declared, the proof, and — for the owner — the decision. A declaration is
/// only a claim: the payment becomes "Payé" when the owner validates it, not before.
class PaymentDetailScreen extends ConsumerStatefulWidget {
  const PaymentDetailScreen({super.key, required this.paymentId, this.fromTill = false});

  final String paymentId;

  /// Arrived here right after declaring at the till: the way out is a new sale.
  final bool fromTill;

  @override
  ConsumerState<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends ConsumerState<PaymentDetailScreen> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(paymentProvider(widget.paymentId));
    ref.invalidate(paymentsListProvider);
    ref.invalidate(paymentSummaryProvider);
    // A validated payment records a sale, which moves the stock.
    ref.invalidate(productsListProvider);
    ref.invalidate(salesHistoryProvider);
  }

  /// Runs one server action, refreshing everything that depends on it and showing any refusal.
  Future<void> _run(Future<Object?> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      if (mounted && done != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(ManualPayment payment) async {
    final money = formatMoney(payment.amount, currency: payment.currency);
    final reference = payment.declaration?.transactionReference;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Valider ce paiement ?'),
            content: Text(
              'Vérifiez dans votre application ${payment.method.displayName} ou dans vos SMS que vous '
              'avez bien reçu $money'
              '${reference == null ? '' : ' avec la référence $reference'}.\n\n'
              'La vente sera alors enregistrée.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Pas encore'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Valider le paiement'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(paymentsApiProvider).verify(payment.id), done: 'Paiement validé.');
  }

  Future<void> _reject(ManualPayment payment) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectDialog(),
    );
    if (reason == null) return;
    await _run(
      () => ref.read(paymentsApiProvider).reject(payment.id, reason: reason),
      done: 'Paiement refusé.',
    );
  }

  Future<void> _cancel(ManualPayment payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Annuler ce paiement ?'),
            content: const Text('Aucune vente ne sera enregistrée.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Non'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Annuler le paiement'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(paymentsApiProvider).cancel(payment.id), done: 'Paiement annulé.');
  }

  Future<void> _tellCustomer(ManualPayment payment) async {
    final business = ref.read(activeBusinessProvider)?.name;
    final money = formatMoney(payment.amount, currency: payment.currency);
    final text =
        payment.isVerified
            ? 'Votre paiement de $money a été confirmé.${business == null ? '' : ' Merci ! — $business'}'
            : 'Votre paiement n’a pas pu être confirmé.'
                '${payment.rejectionReason == null ? '' : ' Motif : ${payment.rejectionReason}.'}';
    await ref.read(textSharerProvider)(text);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(paymentProvider(widget.paymentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paiement'),
        leading:
            widget.fromTill
                ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Fermer',
                  onPressed: () => context.go('/pos'),
                )
                : null,
      ),
      body: SafeArea(
        child: AsyncView(
          value: async,
          onRetry: () => ref.invalidate(paymentProvider(widget.paymentId)),
          data:
              (payment) => RefreshIndicator(
                onRefresh: () async => ref.refresh(paymentProvider(widget.paymentId).future),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _StatusBanner(payment: payment),
                    const SizedBox(height: 12),
                    _SummaryCard(payment: payment),
                    if (payment.declaration != null) ...[
                      const SizedBox(height: 12),
                      _DeclarationCard(payment: payment),
                    ],
                    const SizedBox(height: 16),
                    _Actions(
                      payment: payment,
                      busy: _busy,
                      fromTill: widget.fromTill,
                      onVerify: () => _verify(payment),
                      onReject: () => _reject(payment),
                      onCancel: () => _cancel(payment),
                      onTellCustomer: () => _tellCustomer(payment),
                      onFinishSale:
                          () => _run(
                            () => ref.read(paymentsApiProvider).verify(payment.id),
                            done: 'Vente enregistrée.',
                          ),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }
}

class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.payment});

  final ManualPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(canVerifyPaymentsProvider);
    final color = statusColor(payment.status);

    late final IconData icon;
    late final String title;
    String? detail;
    switch (payment.status) {
      case PaymentStatus.pending:
        icon = Icons.hourglass_empty;
        title = 'En attente';
        detail = 'Le client n’a pas encore déclaré son paiement.';
      case PaymentStatus.submitted:
        icon = Icons.hourglass_top;
        title = 'Paiement envoyé – En attente de vérification';
        detail =
            owner
                ? 'Vérifiez que l’argent est bien arrivé avant de valider.'
                : 'Le propriétaire doit vérifier ce paiement.';
      case PaymentStatus.verified:
        icon = Icons.check_circle;
        title = 'Paiement confirmé';
        detail =
            payment.needsAttention
                ? 'Validé, mais la vente n’a pas pu être enregistrée : terminez l’enregistrement ci-dessous.'
                : payment.sale == null
                ? null
                : 'La vente ${payment.sale!.saleNumber} est enregistrée.';
      case PaymentStatus.rejected:
        icon = Icons.cancel;
        title = 'Paiement refusé';
        detail = payment.rejectionReason == null ? null : 'Motif : ${payment.rejectionReason}';
      default:
        icon = Icons.block;
        title = 'Paiement annulé';
        detail = 'Aucune vente n’a été enregistrée.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
                if (detail != null) ...[const SizedBox(height: 4), Text(detail)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.payment});

  final ManualPayment payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final method = payment.method;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Montant', style: theme.textTheme.bodySmall),
            Text(
              formatMoney(payment.amount, currency: payment.currency),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                PaymentOptionLogo(
                  optionId: method.id,
                  provider: method.provider,
                  hasLogo: method.hasLogo,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method.displayName, style: theme.textTheme.titleMedium),
                      Text(
                        [
                          if (method.accountName != null) method.accountName!,
                          if (method.destination != null) method.destination!,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Créé le ${formatDateTime(payment.createdAt)}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _DeclarationCard extends ConsumerWidget {
  const _DeclarationCard({required this.payment});

  final ManualPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = payment.declaration!;
    final theme = Theme.of(context);

    Widget line(String label, String? value) =>
        value == null
            ? const SizedBox.shrink()
            : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 130, child: Text(label, style: theme.textTheme.bodySmall)),
                  Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
            );

    final proof = payment.hasProof ? ref.watch(paymentProofProvider(payment.id)).value : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Déclaré par le client', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Ce que le client affirme : à vérifier, ce n’est pas une preuve.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            line('Payeur', d.payerName),
            line('Téléphone', d.payerPhone),
            line('Référence', d.transactionReference),
            line(
              'Montant envoyé',
              d.amountSent == null ? null : formatMoney(d.amountSent!, currency: payment.currency),
            ),
            line('Date du paiement', d.paidAt == null ? null : formatDateTime(d.paidAt!)),
            line('Déclaré le', d.submittedAt == null ? null : formatDateTime(d.submittedAt!)),
            if (payment.hasProof) ...[
              const SizedBox(height: 4),
              Text('Preuve', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              if (proof == null)
                const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
              else
                GestureDetector(
                  onTap:
                      () => showDialog<void>(
                        context: context,
                        builder:
                            (context) => Dialog(
                              child: InteractiveViewer(
                                child: Image.memory(
                                  proof,
                                  errorBuilder:
                                      (_, _, _) =>
                                          const Icon(Icons.broken_image_outlined, size: 60),
                                ),
                              ),
                            ),
                      ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      proof,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, _, _) => const SizedBox(
                            height: 60,
                            child: Center(child: Icon(Icons.broken_image_outlined)),
                          ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.payment,
    required this.busy,
    required this.fromTill,
    required this.onVerify,
    required this.onReject,
    required this.onCancel,
    required this.onTellCustomer,
    required this.onFinishSale,
  });

  final ManualPayment payment;
  final bool busy;
  final bool fromTill;
  final VoidCallback onVerify;
  final VoidCallback onReject;
  final VoidCallback onCancel;
  final VoidCallback onTellCustomer;
  final VoidCallback onFinishSale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(canVerifyPaymentsProvider);
    final gap = const SizedBox(height: 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (payment.isPending) ...[
          PrimaryButton(
            label: 'J’ai effectué le paiement',
            onPressed: () => context.push('/pos/pay/declare/${payment.id}', extra: payment),
          ),
          gap,
          TextButton(onPressed: busy ? null : onCancel, child: const Text('Annuler ce paiement')),
        ],
        if (payment.isSubmitted && owner) ...[
          PrimaryButton(label: 'Valider le paiement', loading: busy, onPressed: onVerify),
          gap,
          OutlinedButton(
            onPressed: busy ? null : onReject,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Refuser'),
          ),
          gap,
          TextButton(onPressed: busy ? null : onCancel, child: const Text('Annuler ce paiement')),
        ],
        if (payment.isSubmitted && !owner)
          const Text(
            'En attente de la vérification du propriétaire.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        if (payment.isRejected) ...[
          PrimaryButton(
            label: 'Corriger et renvoyer',
            onPressed: () => context.push('/pos/pay/declare/${payment.id}', extra: payment),
          ),
          gap,
          OutlinedButton(onPressed: onTellCustomer, child: const Text('Informer le client')),
        ],
        if (payment.isVerified) ...[
          if (payment.needsAttention && owner)
            PrimaryButton(
              label: 'Terminer l’enregistrement de la vente',
              loading: busy,
              onPressed: onFinishSale,
            ),
          if (payment.saleId != null) ...[
            PrimaryButton(
              label: 'Voir le reçu',
              onPressed: () => context.push('/sales/${payment.saleId}'),
            ),
            gap,
          ],
          OutlinedButton(
            onPressed: onTellCustomer,
            child: const Text('Envoyer la confirmation au client'),
          ),
        ],
        if (fromTill) ...[
          gap,
          OutlinedButton.icon(
            onPressed: () => context.go('/pos'),
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Nouvelle vente'),
          ),
        ],
      ],
    );
  }
}

/// Asks why the payment is refused: a suggested reason (or none) and free text.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Refuser ce paiement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Le motif sera montré au client.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final reason in rejectionReasons)
                  ActionChip(
                    label: Text(reason),
                    onPressed: () => setState(() => _controller.text = reason),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Refuser le paiement'),
        ),
      ],
    );
  }
}
