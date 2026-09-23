import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/paginated.dart';
import 'sale_models.dart';

class SalesApi {
  SalesApi(this._dio);

  final Dio _dio;

  Future<Sale> checkout(CheckoutRequest request) async {
    try {
      final response = await _dio.post('/sales', data: request.toJson());
      return Sale.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Sale> get(String id) async {
    try {
      final response = await _dio.get('/sales/$id');
      return Sale.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Paginated<Sale>> list({int page = 1, int pageSize = 50}) async {
    try {
      final response = await _dio.get(
        '/sales',
        queryParameters: {'page': page, 'pageSize': pageSize},
      );
      return Paginated.fromJson(response.data as Map<String, dynamic>, Sale.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Cancels a sale: stock is restored and any remaining credit on it is cancelled.
  Future<Sale> voidSale(String id) async {
    try {
      final response = await _dio.post('/sales/$id/void');
      return Sale.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
