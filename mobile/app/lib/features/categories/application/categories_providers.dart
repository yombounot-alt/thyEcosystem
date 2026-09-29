import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_core/thy_core.dart';

import '../data/categories_api.dart';
import '../data/category_models.dart';

final categoriesApiProvider = Provider<CategoriesApi>((ref) {
  return CategoriesApi(ref.watch(dioProvider));
});

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(categoriesApiProvider).list();
});
