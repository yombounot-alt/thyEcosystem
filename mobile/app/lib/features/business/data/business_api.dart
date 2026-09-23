import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

class CreateBusinessResult {
  const CreateBusinessResult({required this.businessId, required this.accessToken});

  final String businessId;

  /// Access token that already carries the new business (the session's refresh token is unchanged).
  final String accessToken;
}

/// Business categories per the product brief (écran 05).
const businessTypes = <String, String>{
  'commerce': 'Commerce',
  'restaurant': 'Restaurant',
  'services': 'Services',
  'pharmacie': 'Pharmacie',
  'mode': 'Mode',
  'electronique': 'Électronique',
  'alimentation': 'Alimentation',
  'autre': 'Autre',
};

/// Full business record (the auth profile only carries name/currency/role).
class BusinessDetails {
  const BusinessDetails({
    required this.id,
    required this.name,
    required this.currency,
    this.phone,
    this.address,
  });

  final String id;
  final String name;
  final String currency;
  final String? phone;
  final String? address;

  factory BusinessDetails.fromJson(Map<String, dynamic> json) {
    return BusinessDetails(
      id: json['id'] as String,
      name: json['name'] as String,
      currency: json['currency'] as String,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
    );
  }
}

class BusinessApi {
  BusinessApi(this._dio);

  final Dio _dio;

  Future<BusinessDetails> details(String businessId) async {
    try {
      final response = await _dio.get('/businesses/$businessId');
      return BusinessDetails.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<CreateBusinessResult> create({
    required String name,
    required String businessType,
    String? currency,
    String? phone,
    String? address,
  }) async {
    try {
      final response = await _dio.post(
        '/businesses',
        data: {
          'name': name,
          'businessType': businessType,
          if (currency != null && currency.isNotEmpty) 'currency': currency,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (address != null && address.isNotEmpty) 'address': address,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return CreateBusinessResult(
        businessId: (data['business'] as Map<String, dynamic>)['id'] as String,
        accessToken: data['accessToken'] as String,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
