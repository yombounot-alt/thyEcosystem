import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/offline/offline_providers.dart';
import '../../../core/theme/app_theme.dart';
import 'pending_sales_repository.dart';
import 'sales_sync_service.dart';

String _sales(int n) => '$n vente${n > 1 ? 's' : ''}';

/// The one place that says what the network is doing to the shop's data: offline, sales waiting
/// to be sent, sales the server refused. Hidden when everything is in order.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectionStatusProvider);
    final pending = ref.watch(activePendingSalesProvider);
    final syncing = ref.watch(salesSyncingProvider);

    final failed = pending.where((s) => s.isFailed).length;
    final waiting = pending.length - failed;
    if (online && pending.isEmpty) return const SizedBox.shrink();

    final Color color;
    final IconData icon;
    final String text;
    if (failed > 0) {
      color = AppColors.danger;
      icon = Icons.error_outline;
      text =
          '${_sales(failed)} à vérifier : le serveur a refusé ${failed > 1 ? 'ces ventes' : 'cette vente'}.';
    } else if (syncing) {
      color = AppColors.warning;
      icon = Icons.sync;
      text = 'Envoi de ${_sales(waiting)}…';
    } else if (waiting > 0) {
      color = AppColors.warning;
      icon = online ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined;
      text =
          online
              ? '${_sales(waiting)} à envoyer.'
              : 'Hors ligne · ${_sales(waiting)} enregistrée${waiting > 1 ? 's' : ''} sur ce téléphone.';
    } else {
      color = AppColors.warning;
      icon = Icons.cloud_off_outlined;
      text = 'Hors ligne — les ventes seront enregistrées sur ce téléphone.';
    }

    return Material(
      color: color.withValues(alpha: 0.14),
      child: InkWell(
        onTap: pending.isEmpty ? null : () => context.push('/sales/pending'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              syncing && failed == 0
                  ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                  : Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (pending.isNotEmpty) const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
