import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_view.dart';
import '../application/inventory_providers.dart';
import 'movement_tile.dart';

class StockHistoryScreen extends ConsumerWidget {
  const StockHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(stockMovementsProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Mouvements de stock')),
      body: AsyncView(
        value: movements,
        onRetry: () => ref.invalidate(stockMovementsProvider),
        data: (page) {
          if (page.items.isEmpty) {
            return const EmptyState(
              icon: Icons.swap_vert,
              message: 'Aucun mouvement de stock pour le moment.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(stockMovementsProvider);
              await ref.read(stockMovementsProvider(null).future);
            },
            child: ListView.separated(
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder:
                  (context, i) => MovementTile(movement: page.items[i], showProductName: true),
            ),
          );
        },
      ),
    );
  }
}
