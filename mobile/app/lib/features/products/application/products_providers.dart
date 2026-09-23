import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/providers.dart';
import '../../sales/offline/pending_sales_repository.dart';
import '../data/product_models.dart';
import '../data/products_api.dart';

final productsApiProvider = Provider<ProductsApi>((ref) {
  return ProductsApi(ref.watch(dioProvider));
});

enum ProductStatusFilter { all, lowStock, outOfStock, inactive }

/// Family key for the product list — needs value equality so identical filters share a cache entry.
class ProductFilter {
  const ProductFilter({this.search = '', this.categoryId, this.status = ProductStatusFilter.all});

  final String search;
  final String? categoryId;
  final ProductStatusFilter status;

  @override
  bool operator ==(Object other) =>
      other is ProductFilter &&
      other.search == search &&
      other.categoryId == categoryId &&
      other.status == status;

  @override
  int get hashCode => Object.hash(search, categoryId, status);
}

final productsListProvider = FutureProvider.autoDispose.family<List<Product>, ProductFilter>((
  ref,
  filter,
) async {
  final api = ref.watch(productsApiProvider);
  final pending = ref.watch(pendingStockProvider);

  switch (filter.status) {
    case ProductStatusFilter.lowStock:
      // The endpoint has no search/category params, so those are applied here.
      final lowStock = await api.lowStock();
      final query = filter.search.toLowerCase();
      return netOfPendingSales(
        lowStock.where((p) {
          final matchesSearch = query.isEmpty || p.name.toLowerCase().contains(query);
          final matchesCategory = filter.categoryId == null || p.categoryId == filter.categoryId;
          return matchesSearch && matchesCategory;
        }).toList(),
        pending,
      );
    case ProductStatusFilter.inactive:
      final page = await api.list(
        search: filter.search,
        categoryId: filter.categoryId,
        isActive: false,
      );
      return netOfPendingSales(page.items, pending);
    case ProductStatusFilter.outOfStock:
      final page = await api.list(search: filter.search, categoryId: filter.categoryId);
      return netOfPendingSales(page.items, pending).where((p) => p.isOutOfStock).toList();
    case ProductStatusFilter.all:
      final page = await api.list(search: filter.search, categoryId: filter.categoryId);
      return netOfPendingSales(page.items, pending);
  }
});

final productProvider = FutureProvider.autoDispose.family<Product, String>((ref, id) async {
  final product = await ref.watch(productsApiProvider).get(id);
  return netOfPendingSales([product], ref.watch(pendingStockProvider)).single;
});

/// Stock minus what was sold but has not reached the server yet.
List<Product> netOfPendingSales(List<Product> products, PendingStock pending) {
  return [
    for (final p in products)
      pending.of(p.id) > 0 ? p.withStock(p.currentStock - pending.of(p.id)) : p,
  ];
}

/// Family key for a product photo. [imageKey] changes on every upload, so a new photo is a new
/// cache entry and the old bytes are never shown by mistake.
typedef ProductImageRef = ({String productId, String imageKey});

/// The photo bytes (fetched through the authenticated API client), or null when they cannot be
/// loaded — the caller then falls back to the product's initial. Kept alive so lists don't refetch.
final productImageProvider = FutureProvider.family<Uint8List?, ProductImageRef>((ref, image) async {
  try {
    return await ref.watch(productsApiProvider).fetchImage(image.productId);
  } on ApiException {
    return null;
  }
});
