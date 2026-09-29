import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_design_system/thy_design_system.dart';
import 'package:thy_core/thy_core.dart';

import '../application/subscription_providers.dart';
import '../data/subscription_api.dart';

/// Limits shown with their usage, in this order. `locations.max` has no usage yet (one location).
const _limits = <String, ({String label, String? hint})>{
  'members.max': (
    label: "Membres de l'équipe",
    hint: 'Vous compris, invitations en attente comprises',
  ),
  'products.max': (label: 'Produits actifs', hint: 'Un produit désactivé libère sa place'),
  'locations.max': (label: 'Points de vente', hint: null),
};

const _switches = <String, String>{'reports.export': 'Export des rapports'};

String statusLabel(String status) => switch (status) {
  'TRIALING' => "Période d'essai",
  'ACTIVE' => 'Active',
  'PAST_DUE' => 'Paiement en retard',
  'GRACE' => 'Délai de grâce',
  'EXPIRED' => 'Expirée',
  'CANCELED' => 'Résiliée',
  _ => status,
};

/// "Mon offre": the business's plan, what it allows and how much is used. Read-only: the server
/// enforces the limits, this screen explains them.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(subscriptionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon offre')),
      body: AsyncView<SubscriptionSummary>(
        value: summary,
        onRetry: () => ref.invalidate(subscriptionProvider),
        data:
            (s) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(subscriptionProvider);
                await ref.read(subscriptionProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _PlanCard(summary: s),
                  const SizedBox(height: 16),
                  Text('Ce que votre offre permet', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final entry in _limits.entries)
                    if (s.entitlements.containsKey(entry.key))
                      _LimitTile(
                        label: entry.value.label,
                        hint: entry.value.hint,
                        limit: s.limit(entry.key),
                        used: s.usage[entry.key],
                      ),
                  for (final entry in _switches.entries)
                    if (s.entitlements.containsKey(entry.key))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          s.granted(entry.key) ? Icons.check_circle : Icons.remove_circle_outline,
                          color:
                              s.granted(entry.key)
                                  ? context.colors.success
                                  : context.colors.onSurfaceMuted,
                        ),
                        title: Text(entry.value),
                        subtitle: Text(s.granted(entry.key) ? 'Inclus' : 'Non inclus'),
                      ),
                  const SizedBox(height: 16),
                  Text(
                    "Le passage à une offre supérieure depuis l'application arrive bientôt. "
                    'Vos données ne sont jamais supprimées quand une limite est atteinte.',
                    style: TextStyle(color: context.colors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.summary});

  final SubscriptionSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final end = s.currentPeriodEnd;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Offre ${s.planName}', style: Theme.of(context).textTheme.titleLarge),
                ),
                Chip(
                  label: Text(statusLabel(s.status)),
                  backgroundColor:
                      s.isDegraded || s.status == 'PAST_DUE'
                          ? context.colors.warning.withValues(alpha: 0.2)
                          : context.colors.success.withValues(alpha: 0.15),
                ),
              ],
            ),
            if (end != null) ...[
              const SizedBox(height: 4),
              Text('Jusqu\'au ${formatDay(end.toLocal())}'),
            ],
            if (s.isDegraded) ...[
              const SizedBox(height: 8),
              Text(
                "Votre offre n'est plus active : les limites de l'offre gratuite s'appliquent. "
                'Toutes vos données restent consultables.',
                style: TextStyle(color: context.colors.onSurfaceMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LimitTile extends StatelessWidget {
  const _LimitTile({
    required this.label,
    required this.hint,
    required this.limit,
    required this.used,
  });

  final String label;
  final String? hint;

  /// Null: unlimited.
  final int? limit;

  /// Null: not measured for this limit.
  final int? used;

  @override
  Widget build(BuildContext context) {
    final max = limit;
    final count = used;
    final full = max != null && count != null && count >= max;
    final String value;
    if (max == null) {
      value = count == null ? 'Illimité' : '$count · illimité';
    } else {
      value = count == null ? '$max' : '$count / $max';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: full ? context.colors.danger : context.colors.onSurface,
                ),
              ),
            ],
          ),
          if (max != null && max > 0 && count != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (count / max).clamp(0, 1).toDouble(),
                minHeight: 6,
                color: full ? context.colors.danger : context.colors.primary,
                backgroundColor: context.colors.border,
                semanticsLabel: label,
              ),
            ),
          ],
          if (full) ...[
            const SizedBox(height: 4),
            Text('Limite atteinte', style: TextStyle(color: context.colors.danger)),
          ] else if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
