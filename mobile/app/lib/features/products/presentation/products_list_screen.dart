import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../../categories/application/categories_providers.dart';
import '../application/products_providers.dart';
import '../data/product_models.dart';
import 'product_photo.dart';

const _statusLabels = {
  ProductStatusFilter.all: 'Tous',
  ProductStatusFilter.lowStock: 'Stock faible',
  ProductStatusFilter.outOfStock: 'Rupture',
  ProductStatusFilter.inactive: 'Inactifs',
};

class ProductsListScreen extends ConsumerStatefulWidget {
  const ProductsListScreen({super.key});

  @override
  ConsumerState<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends ConsumerState<ProductsListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  String? _categoryId;
  ProductStatusFilter _status = ProductStatusFilter.all;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ProductFilter(search: _search, categoryId: _categoryId, status: _status);
    final products = ref.watch(productsListProvider(filter));
    final categories = ref.watch(categoriesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Mouvements de stock',
            onPressed: () => context.push('/stock/history'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/products/new'),
        icon: const Icon(Icons.add),
        label: const Text('Produit'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un produit',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                // A null menu value is treated as "dismissed" by Flutter, so "all" uses ''.
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.filter_list,
                    color: _categoryId == null ? null : AppColors.primary,
                  ),
                  tooltip: 'Filtrer par catégorie',
                  onSelected: (id) => setState(() => _categoryId = id.isEmpty ? null : id),
                  itemBuilder:
                      (_) => [
                        const PopupMenuItem<String>(
                          value: '',
                          child: Text('Toutes les catégories'),
                        ),
                        for (final category in categories)
                          PopupMenuItem<String>(value: category.id, child: Text(category.name)),
                      ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final entry in _statusLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _status == entry.key,
                      onSelected: (_) => setState(() => _status = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: products,
              onRetry: () => ref.invalidate(productsListProvider),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message:
                        _search.isEmpty && _status == ProductStatusFilter.all
                            ? 'Aucun produit pour le moment.\nAppuyez sur « Produit » pour ajouter le premier.'
                            : 'Aucun produit ne correspond à ce filtre.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(productsListProvider);
                    await ref.read(productsListProvider(filter).future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _ProductTile(product: items[i]),
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

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final Color stockColor;
    if (product.isOutOfStock) {
      stockColor = AppColors.danger;
    } else if (product.isLowStock) {
      stockColor = AppColors.warning;
    } else {
      stockColor = AppColors.textPrimary;
    }

    final subtitle = [
      if (product.categoryName != null) product.categoryName!,
      formatMoney(product.salePrice, currency: currency),
      if (!product.isActive) 'Inactif',
    ].join(' · ');

    return ListTile(
      onTap: () => context.push('/products/${product.id}'),
      leading: ProductAvatar(product: product),
      title: Text(product.name),
      subtitle: Text(subtitle),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatQuantity(product.currentStock),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: stockColor),
          ),
          Text(
            formatUnit(product.unit, product.currentStock),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
