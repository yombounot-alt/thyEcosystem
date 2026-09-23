import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'dashboard_models.dart';

class DashboardApi {
  DashboardApi(this._dio);

  final Dio _dio;

  /// The server knows today/week/month; the calendar year is sent as a custom range.
  Map<String, dynamic> _periodQuery(DashboardPeriod period) {
    switch (period) {
      case DashboardPeriod.today:
        return {'period': 'today'};
      case DashboardPeriod.week:
        return {'period': 'week'};
      case DashboardPeriod.month:
        return {'period': 'month'};
      case DashboardPeriod.year:
        final now = DateTime.now();
        return {
          'period': 'custom',
          'from': DateTime(now.year).toUtc().toIso8601String(),
          'to': now.toUtc().toIso8601String(),
        };
    }
  }

  Future<DashboardSummary> summary(DashboardPeriod period) async {
    try {
      final response = await _dio.get('/dashboard/summary', queryParameters: _periodQuery(period));
      return DashboardSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Revenue per day for the last [days] days, oldest first (days without sales are 0).
  Future<List<SalesChartPoint>> salesChart({int days = 7}) async {
    try {
      final response = await _dio.get('/dashboard/sales-chart', queryParameters: {'days': days});
      return (response.data as List<dynamic>)
          .map((e) => SalesChartPoint.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<List<TopProduct>> topProducts(DashboardPeriod period, {int limit = 5}) async {
    try {
      final response = await _dio.get(
        '/dashboard/top-products',
        queryParameters: {..._periodQuery(period), 'limit': limit},
      );
      return (response.data as List<dynamic>)
          .map((e) => TopProduct.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
