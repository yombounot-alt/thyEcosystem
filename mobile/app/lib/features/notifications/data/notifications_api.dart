import 'package:dio/dio.dart';
import 'package:thy_core/thy_core.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;

  /// Routing data sent by the server (`productId`, `businessId`, …) — strings only.
  final Map<String, String> data;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  AppNotification markedRead() => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    readAt: readAt ?? DateTime.now(),
    createdAt: createdAt,
  );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    data: {
      for (final e in ((json['data'] as Map<String, dynamic>?) ?? const {}).entries)
        e.key: e.value.toString(),
    },
    readAt: json['readAt'] == null ? null : DateTime.parse(json['readAt'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class NotificationsPage {
  const NotificationsPage({required this.items, required this.nextCursor});

  final List<AppNotification> items;
  final String? nextCursor;
}

/// The signed-in user's inbox (in-app notifications, across all their businesses).
class NotificationsApi {
  NotificationsApi(this._dio);

  final Dio _dio;

  Future<NotificationsPage> list({String? cursor, int limit = 30}) async {
    try {
      final response = await _dio.get(
        '/me/notifications',
        queryParameters: {'limit': limit, if (cursor != null) 'cursor': cursor},
      );
      final json = response.data as Map<String, dynamic>;
      return NotificationsPage(
        items: [
          for (final n in json['items'] as List<dynamic>)
            AppNotification.fromJson(n as Map<String, dynamic>),
        ],
        nextCursor: json['nextCursor'] as String?,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<int> unreadCount() async {
    try {
      final response = await _dio.get('/me/notifications/unread-count');
      return (response.data as Map<String, dynamic>)['unread'] as int;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _dio.post('/me/notifications/$id/read');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _dio.post('/me/notifications/read-all');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
