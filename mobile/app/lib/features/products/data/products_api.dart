import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/paginated.dart';
import 'product_models.dart';

class ProductsApi {
  ProductsApi(this._dio);

  final Dio _dio;

  Future<Paginated<Product>> list({
    String? search,
    String? categoryId,
    bool? isActive,
    int page = 1,
    int pageSize = 100,
  }) async {
    try {
      final response = await _dio.get(
        '/products',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (categoryId != null) 'categoryId': categoryId,
          if (isActive != null) 'isActive': isActive,
          'page': page,
          'pageSize': pageSize,
        },
      );
      return Paginated.fromJson(response.data as Map<String, dynamic>, Product.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<List<Product>> lowStock() async {
    try {
      final response = await _dio.get('/products/low-stock');
      return (response.data as List<dynamic>)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Product> get(String id) async {
    try {
      final response = await _dio.get('/products/$id');
      return Product.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Product> create(ProductInput input) async {
    try {
      final response = await _dio.post('/products', data: input.toCreateJson());
      return Product.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Product> update(String id, ProductInput input) async {
    try {
      final response = await _dio.patch('/products/$id', data: input.toUpdateJson());
      return Product.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Sets or replaces the photo. The server identifies the format from the bytes themselves.
  Future<Product> uploadImage(String id, Uint8List bytes, String filename) async {
    try {
      final response = await _dio.put(
        '/products/$id/image',
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
      );
      return Product.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Product> deleteImage(String id) async {
    try {
      final response = await _dio.delete('/products/$id/image');
      return Product.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Uint8List> fetchImage(String id) async {
    try {
      final response = await _dio.get<List<int>>(
        '/products/$id/image',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Soft delete: history (sales, movements) referencing the product stays intact.
  Future<void> deactivate(String id) async {
    try {
      await _dio.delete('/products/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> reactivate(String id) async {
    try {
      await _dio.patch('/products/$id', data: {'isActive': true});
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
