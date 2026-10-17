import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';
import 'package:thy_core/thy_core.dart';

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

    final ThyTone tone;
    final IconData icon;
    final String text;
    if (failed > 0) {
      tone = ThyTone.danger;
      icon = Icons.error_outline;
      text =
          '${_sales(failed)} à vérifier : le serveur a refusé ${failed > 1 ? 'ces ventes' : 'cette vente'}.';
    } else if (syncing) {
      tone = ThyTone.warning;
      icon = Icons.sync;
      text = 'Envoi de ${_sales(waiting)}…';
    } else if (waiting > 0) {
      tone = ThyTone.warning;
      icon = online ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined;
      text =
          online
              ? '${_sales(waiting)} à envoyer.'
              : 'Hors ligne · ${_sales(waiting)} enregistrée${waiting > 1 ? 's' : ''} sur ce téléphone.';
    } else {
      tone = ThyTone.warning;
      icon = Icons.cloud_off_outlined;
      text = 'Hors ligne — les ventes seront enregistrées sur ce téléphone.';
    }

    return ThyBanner(
      message: text,
      tone: tone,
      icon: icon,
      busy: syncing && failed == 0,
      onTap: pending.isEmpty ? null : () => context.push('/sales/pending'),
      actionLabel: pending.isEmpty ? null : 'Voir',
    );
  }
}
