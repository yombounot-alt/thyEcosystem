import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'category_models.dart';

class CategoriesApi {
  CategoriesApi(this._dio);

  final Dio _dio;

  Future<List<Category>> list() async {
    try {
      final response = await _dio.get('/categories');
      return (response.data as List<dynamic>)
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Category> create(String name) async {
    try {
      final response = await _dio.post('/categories', data: {'name': name});
      return Category.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Category> rename(String id, String name) async {
    try {
      final response = await _dio.patch('/categories/$id', data: {'name': name});
      return Category.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('/categories/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
