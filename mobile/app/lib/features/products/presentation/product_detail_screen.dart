import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../inventory/presentation/movement_tile.dart';
import '../application/products_providers.dart';
import '../data/product_models.dart';
import 'product_photo.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: Text(product.value?.name ?? 'Produit'),
        actions: [
          if (product.hasValue)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Modifier',
              onPressed: () => context.push('/products/$productId/edit'),
            ),
        ],
      ),
      body: AsyncView(
        value: product,
        onRetry: () => ref.invalidate(productProvider(productId)),
        data: (p) => _ProductDetailBody(product: p),
      ),
    );
  }
}

class _ProductDetailBody extends ConsumerWidget {
  const _ProductDetailBody({required this.product});

  final Product product;

  Future<void> _toggleActive(BuildContext context, WidgetRef ref) async {
    if (product.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Désactiver ce produit ?'),
              content: const Text(
                "Il n'apparaîtra plus à la caisse. L'historique des ventes et du stock est conservé.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Désactiver'),
                ),
              ],
            ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    try {
      final api = ref.read(productsApiProvider);
      if (product.isActive) {
        await api.deactivate(product.id);
      } else {
        await api.reactivate(product.id);
      }
      ref.invalidate(productProvider(product.id));
      ref.invalidate(productsListProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final movements = ref.watch(stockMovementsProvider(product.id));
    final textTheme = Theme.of(context).textTheme;

    final Color stockColor;
    final String stockStatus;
    if (product.isOutOfStock) {
      stockColor = AppColors.danger;
      stockStatus = 'Rupture de stock';
    } else if (product.isLowStock) {
      stockColor = AppColors.warning;
      stockStatus = 'Stock faible (minimum ${formatQuantity(product.lowStockThreshold!)})';
    } else {
      stockColor = AppColors.success;
      stockStatus = 'En stock';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!product.isActive)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Chip(
              avatar: Icon(Icons.visibility_off_outlined, size: 18),
              label: Text('Produit inactif — masqué de la caisse'),
            ),
          ),
        if (product.hasImage) ...[
          // A square, like the preview in the form: a wide banner would crop most of a phone photo.
          Center(child: ProductPhoto(product: product, width: 200, height: 200)),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stock actuel', style: textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        '${formatQuantity(product.currentStock)} ${formatUnit(product.unit, product.currentStock)}',
                        style: textTheme.headlineMedium?.copyWith(color: stockColor),
                      ),
                      const SizedBox(height: 4),
                      Text(stockStatus, style: TextStyle(color: stockColor)),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/products/${product.id}/stock'),
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Ajuster'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _InfoRow("Prix d'achat", formatMoney(product.purchasePrice, currency: currency)),
                _InfoRow('Prix de vente', formatMoney(product.salePrice, currency: currency)),
                _InfoRow(
                  'Marge',
                  '${formatMoney(product.margin, currency: currency)} '
                      '(${product.marginPercent.toStringAsFixed(0)} %)',
                ),
                _InfoRow('Valeur du stock', formatMoney(product.stockValue, currency: currency)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _InfoRow('Catégorie', product.categoryName ?? '—'),
                _InfoRow('SKU', product.sku ?? '—'),
                _InfoRow('Code-barres', product.barcode ?? '—'),
                if (product.description != null && product.description!.isNotEmpty)
                  _InfoRow('Description', product.description!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _toggleActive(context, ref),
          icon: Icon(product.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          label: Text(product.isActive ? 'Désactiver le produit' : 'Réactiver le produit'),
        ),
        const SizedBox(height: 24),
        Text('Derniers mouvements', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        AsyncView(
          value: movements,
          onRetry: () => ref.invalidate(stockMovementsProvider(product.id)),
          data: (page) {
            if (page.items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Aucun mouvement enregistré.'),
              );
            }
            return Column(
              children: [
                for (final movement in page.items.take(10)) MovementTile(movement: movement),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(width: 16),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
