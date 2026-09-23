import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../offline/pending_sale.dart';
import '../offline/pending_sales_repository.dart';

/// Removing a queued sale loses it for good, so it is always confirmed — and worded for what it
/// really means: the sale never reached the server.
Future<void> confirmDeletePendingSale(BuildContext context, WidgetRef ref, PendingSale sale) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text('Supprimer la vente ${sale.receipt.saleNumber} ?'),
          content: const Text(
            "Cette vente n'a pas encore été enregistrée sur le serveur : elle sera perdue et le stock "
            "sera rétabli. À faire seulement si la vente n'a pas eu lieu.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Garder la vente'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
  );
  if (confirmed != true) return;

  await ref.read(pendingSalesProvider.notifier).remove(sale.id);
  if (context.mounted && GoRouterState.of(context).uri.path.startsWith('/sales/pending/')) {
    context.go('/sales/pending');
  }
}
