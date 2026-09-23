import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/paginated.dart';
import 'customer_models.dart';

class CustomersApi {
  CustomersApi(this._dio);

  final Dio _dio;

  Future<Paginated<Customer>> list({String? search, int page = 1, int pageSize = 100}) async {
    try {
      final response = await _dio.get(
        '/customers',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'pageSize': pageSize,
        },
      );
      return Paginated.fromJson(response.data as Map<String, dynamic>, Customer.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Customer> get(String id) async {
    try {
      final response = await _dio.get('/customers/$id');
      return Customer.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Customer> create({
    required String fullName,
    String? phone,
    String? address,
    String? notes,
  }) async {
    try {
      final input = CustomerInput(
        fullName: fullName,
        phone: (phone == null || phone.isEmpty) ? null : phone,
        address: (address == null || address.isEmpty) ? null : address,
        notes: (notes == null || notes.isEmpty) ? null : notes,
      );
      final response = await _dio.post('/customers', data: input.toCreateJson());
      return Customer.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Customer> update(String id, CustomerInput input) async {
    try {
      final response = await _dio.patch('/customers/$id', data: input.toUpdateJson());
      return Customer.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Refused (409) when the customer has sales or credits attached.
  Future<void> delete(String id) async {
    try {
      await _dio.delete('/customers/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<List<CustomerCredit>> credits(String customerId) async {
    try {
      final response = await _dio.get('/customers/$customerId/credits');
      return (response.data as List<dynamic>)
          .map((e) => CustomerCredit.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Debts and payments merged, oldest first.
  Future<List<StatementEntry>> statement(String customerId) async {
    try {
      final response = await _dio.get('/customers/$customerId/statement');
      return (response.data as List<dynamic>)
          .map((e) => StatementEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// A debt not tied to a sale (goods given before, loan, …).
  Future<void> grantCredit(
    String customerId, {
    required double amount,
    DateTime? dueDate,
    String? note,
  }) async {
    try {
      await _dio.post(
        '/customers/$customerId/credits',
        data: {
          'amount': amount,
          if (dueDate != null) 'dueDate': DateFormat('yyyy-MM-dd').format(dueDate),
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Repays debts oldest-first (FIFO); the server refuses more than the customer owes.
  Future<void> recordPayment(
    String customerId, {
    required double amount,
    required String method,
    String? note,
  }) async {
    try {
      await _dio.post(
        '/customers/$customerId/credit-payments',
        data: {
          'amount': amount,
          'method': method,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Everything still owed across customers, earliest due date first.
  Future<Paginated<CustomerCredit>> outstandingCredits({int page = 1, int pageSize = 100}) async {
    try {
      final response = await _dio.get(
        '/credits',
        queryParameters: {'status': 'outstanding', 'page': page, 'pageSize': pageSize},
      );
      return Paginated.fromJson(response.data as Map<String, dynamic>, CustomerCredit.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
