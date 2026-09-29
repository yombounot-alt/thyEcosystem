import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_core/thy_core.dart';

import '../data/sale_models.dart';
import '../data/sales_api.dart';

final salesApiProvider = Provider<SalesApi>((ref) => SalesApi(ref.watch(dioProvider)));

final saleProvider = FutureProvider.autoDispose.family<Sale, String>((ref, id) {
  return ref.watch(salesApiProvider).get(id);
});

final salesHistoryProvider = FutureProvider.autoDispose<Paginated<Sale>>((ref) {
  return ref.watch(salesApiProvider).list();
});
