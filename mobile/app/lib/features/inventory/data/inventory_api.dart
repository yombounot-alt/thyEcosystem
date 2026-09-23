import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/paginated.dart';
import 'inventory_models.dart';

class InventoryApi {
  InventoryApi(this._dio);

  final Dio _dio;

  Future<Paginated<StockMovement>> list({
    String? productId,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final response = await _dio.get(
        '/inventory/movements',
        queryParameters: {
          if (productId != null) 'productId': productId,
          'page': page,
          'pageSize': pageSize,
        },
      );
      return Paginated.fromJson(response.data as Map<String, dynamic>, StockMovement.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// [type] must be one of purchase_in / adjustment_in / adjustment_out — the server
  /// rejects the others, and rejects any movement that would make stock negative.
  Future<void> record({
    required String productId,
    required String type,
    required double quantity,
    double? unitCost,
    String? note,
  }) async {
    try {
      await _dio.post(
        '/inventory/movements',
        data: {
          'productId': productId,
          'type': type,
          'quantity': quantity,
          if (unitCost != null) 'unitCost': unitCost,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
