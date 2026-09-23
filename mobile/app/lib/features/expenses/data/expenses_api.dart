import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import 'expense_models.dart';

class ExpensesApi {
  ExpensesApi(this._dio);

  final Dio _dio;

  static String _day(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  /// [from]/[to] are inclusive calendar days.
  Future<ExpensePage> list({DateTime? from, DateTime? to, int page = 1, int pageSize = 100}) async {
    try {
      final response = await _dio.get(
        '/expenses',
        queryParameters: {
          if (from != null) 'from': _day(from),
          if (to != null) 'to': _day(to),
          'page': page,
          'pageSize': pageSize,
        },
      );
      return ExpensePage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Expense> get(String id) async {
    try {
      final response = await _dio.get('/expenses/$id');
      return Expense.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Expense> create(ExpenseInput input) async {
    try {
      final response = await _dio.post('/expenses', data: input.toCreateJson());
      return Expense.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Expense> update(String id, ExpenseInput input) async {
    try {
      final response = await _dio.patch('/expenses/$id', data: input.toUpdateJson());
      return Expense.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('/expenses/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
