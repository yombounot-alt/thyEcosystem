import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/paginated.dart';
import '../../../core/providers.dart';
import '../data/sale_models.dart';
import '../data/sales_api.dart';

final salesApiProvider = Provider<SalesApi>((ref) => SalesApi(ref.watch(dioProvider)));

final saleProvider = FutureProvider.autoDispose.family<Sale, String>((ref, id) {
  return ref.watch(salesApiProvider).get(id);
});

final salesHistoryProvider = FutureProvider.autoDispose<Paginated<Sale>>((ref) {
  return ref.watch(salesApiProvider).list();
});
