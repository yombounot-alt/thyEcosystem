import 'package:dio/dio.dart';
import 'package:thy_core/thy_core.dart';

/// Error code the server sends when an action would go past what the business's plan allows.
const entitlementLimitReached = 'ENTITLEMENT_LIMIT_REACHED';

/// The business's plan, what it grants, and how much of each limit is used.
class SubscriptionSummary {
  const SubscriptionSummary({
    required this.planCode,
    required this.planName,
    required this.status,
    required this.currentPeriodEnd,
    required this.entitlements,
    required this.usage,
  });

  final String planCode;
  final String planName;

  /// `TRIALING`, `ACTIVE`, `PAST_DUE`, `GRACE`, `EXPIRED` or `CANCELED`.
  final String status;
  final DateTime? currentPeriodEnd;

  /// Limits (`members.max`: 3; null = unlimited) and switches (`reports.export`: 1 or 0).
  final Map<String, int?> entitlements;

  /// How much of each limit is taken (`members.max`: 2).
  final Map<String, int> usage;

  /// An expired or cancelled plan falls back to the free plan's rights (data is kept).
  bool get isDegraded => status == 'EXPIRED' || status == 'CANCELED';

  int? limit(String code) => entitlements[code];
  bool granted(String code) => (entitlements[code] ?? 0) > 0;

  factory SubscriptionSummary.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] as Map<String, dynamic>;
    return SubscriptionSummary(
      planCode: plan['code'] as String,
      planName: plan['name'] as String,
      status: json['status'] as String,
      currentPeriodEnd:
          json['currentPeriodEnd'] == null
              ? null
              : DateTime.parse(json['currentPeriodEnd'] as String),
      entitlements: {
        for (final e in (json['entitlements'] as Map<String, dynamic>).entries)
          e.key: (e.value as num?)?.toInt(),
      },
      usage: {
        for (final e in (json['usage'] as Map<String, dynamic>).entries)
          e.key: (e.value as num).toInt(),
      },
    );
  }
}

class SubscriptionApi {
  SubscriptionApi(this._dio);

  final Dio _dio;

  Future<SubscriptionSummary> summary(String businessId) async {
    try {
      final response = await _dio.get('/businesses/$businessId/subscription');
      return SubscriptionSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
