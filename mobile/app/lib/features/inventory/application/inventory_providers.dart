import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/paginated.dart';
import '../../../core/providers.dart';
import '../data/inventory_api.dart';
import '../data/inventory_models.dart';

final inventoryApiProvider = Provider<InventoryApi>((ref) {
  return InventoryApi(ref.watch(dioProvider));
});

/// Movements for one product, or for the whole business when [productId] is null.
final stockMovementsProvider = FutureProvider.autoDispose.family<Paginated<StockMovement>, String?>(
  (ref, productId) {
    return ref.watch(inventoryApiProvider).list(productId: productId, pageSize: 50);
  },
);
