import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/paginated.dart';
import '../../sales/data/sale_models.dart';
import 'payment_method_models.dart';
import 'payment_models.dart';

/// Settings: the numbers and codes customers can pay (an option each). Changes are for the owner (the server checks).
class PaymentMethodsApi {
  PaymentMethodsApi(this._dio);

  final Dio _dio;

  Future<List<PaymentOption>> list() async {
    try {
      final response = await _dio.get('/payment-methods');
      return [
        for (final item in response.data as List<dynamic>)
          PaymentOption.fromJson(item as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<PaymentOption> create(PaymentOptionInput input) async {
    try {
      final response = await _dio.post('/payment-methods', data: input.toJson());
      return PaymentOption.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<PaymentOption> update(String id, PaymentOptionInput input) async {
    try {
      final response = await _dio.patch('/payment-methods/$id', data: input.toJson());
      return PaymentOption.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Switches a method on or off without touching anything else.
  Future<PaymentOption> setActive(String id, bool active) async {
    try {
      final response = await _dio.patch('/payment-methods/$id', data: {'isActive': active});
      return PaymentOption.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// A method that was ever used cannot be deleted (the server says so): deactivate it instead.
  Future<void> delete(String id) async {
    try {
      await _dio.delete('/payment-methods/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<PaymentOption> uploadLogo(String id, Uint8List bytes, String filename) async {
    try {
      final response = await _dio.put(
        '/payment-methods/$id/logo',
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
      );
      return PaymentOption.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<PaymentOption> deleteLogo(String id) async {
    try {
      final response = await _dio.delete('/payment-methods/$id/logo');
      return PaymentOption.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Uint8List> fetchLogo(String id) async {
    try {
      final response = await _dio.get<List<int>>(
        '/payment-methods/$id/logo',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}

/// Payments customers make directly to the owner. Only the owner can verify or refuse.
class PaymentsApi {
  PaymentsApi(this._dio);

  final Dio _dio;

  /// Starts a payment for a basket on one method. Only the basket goes to the server — never an
  /// amount: the server prices it. Asking again with the same [clientRequestId] returns the same
  /// payment.
  Future<ManualPayment> start({
    required List<CheckoutLine> items,
    required String paymentMethodId,
    required String clientRequestId,
    double discountTotal = 0,
    String? customerId,
  }) async {
    try {
      final response = await _dio.post(
        '/payments',
        data: {
          'items': items.map((i) => i.toJson()).toList(),
          if (discountTotal > 0) 'discountTotal': discountTotal,
          if (customerId != null) 'customerId': customerId,
          'paymentMethodId': paymentMethodId,
          'clientRequestId': clientRequestId,
        },
      );
      return ManualPayment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<ManualPayment> get(String id) async {
    try {
      final response = await _dio.get('/payments/$id');
      return ManualPayment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Paginated<ManualPayment>> list({String? status, int page = 1, int pageSize = 50}) async {
    try {
      final response = await _dio.get(
        '/payments',
        queryParameters: {if (status != null) 'status': status, 'page': page, 'pageSize': pageSize},
      );
      return Paginated.fromJson(response.data as Map<String, dynamic>, ManualPayment.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<PaymentSummary> summary() async {
    try {
      final response = await _dio.get('/payments/summary');
      return PaymentSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// "J'ai effectué le paiement": records the declaration. The payment then waits for the owner.
  Future<ManualPayment> submit(String id, DeclarationInput input) async {
    try {
      final response = await _dio.post('/payments/$id/submit', data: input.toJson());
      return ManualPayment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Owner only: the money really arrived. Records the sale.
  Future<ManualPayment> verify(String id) async {
    try {
      final response = await _dio.post('/payments/$id/verify');
      return ManualPayment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Owner only. The reason is shown to the payer.
  Future<ManualPayment> reject(String id, {String? reason}) async {
    try {
      final response = await _dio.post(
        '/payments/$id/reject',
        data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
      );
      return ManualPayment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<ManualPayment> cancel(String id) async {
    try {
      final response = await _dio.post('/payments/$id/cancel');
      return ManualPayment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<ManualPayment> uploadProof(String id, Uint8List bytes, String filename) async {
    try {
      final response = await _dio.put(
        '/payments/$id/proof',
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
      );
      return ManualPayment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Uint8List> fetchProof(String id) async {
    try {
      final response = await _dio.get<List<int>>(
        '/payments/$id/proof',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
