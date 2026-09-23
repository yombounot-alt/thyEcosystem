import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'auth_models.dart';

/// Sign-up and sign-in are ONE flow: a code sent by SMS proves the phone number, and the account
/// is created the first time a number is verified.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<void> requestOtp({required String phone}) async {
    try {
      await _dio.post('/auth/otp/request', data: {'phone': phone});
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<TokenPair> verifyOtp({required String phone, required String code}) async {
    try {
      final response = await _dio.post('/auth/otp/verify', data: {'phone': phone, 'code': code});
      return TokenPair.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post('/auth/logout', data: {'refreshToken': refreshToken});
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<UserProfile> me() async {
    try {
      final response = await _dio.get('/me');
      return UserProfile.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> updateFullName(String fullName) async {
    try {
      await _dio.patch('/me', data: {'fullName': fullName});
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Makes [businessId] the active business: returns an access token that carries it.
  Future<String> activateBusiness(String businessId) async {
    try {
      final response = await _dio.post('/businesses/$businessId/activate');
      return (response.data as Map<String, dynamic>)['accessToken'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
