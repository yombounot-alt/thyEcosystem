import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sharing/text_sharer.dart';
import '../../../core/theme/app_theme.dart';
import '../application/receipt_text.dart';
import '../offline/pending_sale.dart';
import '../offline/pending_sales_repository.dart';
import '../offline/sales_sync_service.dart';
import 'pending_sale_actions.dart';
import 'receipt_screen.dart';

/// Receipt of a sale that is still on the phone. Same receipt as any other — the customer is
/// handed it right away — plus a clear note that the server does not have the sale yet.
class PendingReceiptScreen extends ConsumerWidget {
  const PendingReceiptScreen({super.key, required this.pendingId, this.change = 0});

  final String pendingId;
  final double change;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The sale got sent while this screen was open: carry on with the real receipt.
    ref.listen(syncedSalesProvider, (previous, synced) {
      final saleId = synced[pendingId];
      if (saleId != null) context.go('/sales/$saleId?change=${change.toStringAsFixed(2)}');
    });

    final pending = ref.watch(pendingSalesProvider).where((s) => s.id == pendingId).firstOrNull;
    final details = receiptBusiness(ref);

    if (pending == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reçu')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_done_outlined, size: 48, color: AppColors.success),
                const SizedBox(height: 12),
                const Text(
                  "Cette vente n'est plus en attente.\nRetrouvez-la dans l'historique des ventes.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/sales'),
                  child: const Text('Historique'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reçu'),
        leading:
            context.canPop()
                ? null
                : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Fermer',
                  onPressed: () => context.go('/pos'),
                ),
        actions: [
          ReceiptPdfButton(sale: pending.receipt, business: details, change: change),
          PopupMenuButton<String>(
            onSelected: (_) => confirmDeletePendingSale(context, ref, pending),
            itemBuilder:
                (_) => const [PopupMenuItem(value: 'delete', child: Text('Supprimer cette vente'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusNote(pending: pending),
          const SizedBox(height: 12),
          ReceiptCard(sale: pending.receipt, business: details, change: change),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      () => ref.read(textSharerProvider)(
                        buildReceiptText(pending.receipt, details, change: change),
                      ),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Partager'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.go('/pos'),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Nouvelle vente'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusNote extends ConsumerWidget {
  const _StatusNote({required this.pending});

  final PendingSale pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = pending.isFailed;
    final color = failed ? AppColors.danger : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(failed ? Icons.error_outline : Icons.cloud_off_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  failed ? 'Le serveur a refusé cette vente' : 'Vente enregistrée sur ce téléphone',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            failed
                ? pending.lastError ?? 'Raison inconnue.'
                : 'Elle sera envoyée au serveur dès que le réseau sera de retour. '
                    'Le numéro ${pending.receipt.saleNumber} est provisoire : le vrai numéro '
                    "sera attribué à l'envoi.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (failed) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => ref.read(salesSyncServiceProvider).retry(pending.id),
                  child: const Text('Réessayer'),
                ),
                TextButton(
                  onPressed: () => confirmDeletePendingSale(context, ref, pending),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
