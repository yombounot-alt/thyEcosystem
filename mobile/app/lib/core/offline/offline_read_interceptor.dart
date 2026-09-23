import 'package:dio/dio.dart';

import '../api/api_exception.dart';
import 'offline_cache.dart';

/// Scope of the few answers needed before the user (and so the scope) is known: the profile
/// fetched at start-up. Wiped on logout like everything else.
const sessionScope = 'session';

const _cacheablePrefixes = [
  '/me',
  '/businesses',
  '/categories',
  '/products',
  '/customers',
  '/credits',
  '/expenses',
  '/dashboard',
  '/sales',
  '/inventory',
];

/// Cache key of a request: method, path and the query in a stable order.
String cacheKeyFor(RequestOptions options) {
  final entries = options.queryParameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final query = entries.map((e) => '${e.key}=${e.value}').join('&');
  return '${options.method} ${options.path}?$query';
}

/// Two jobs, both about a flaky network:
///
///  * every successful read is remembered, and when the server cannot be reached the last good
///    answer is served instead (marked with `extra['fromCache']`) — HTTP errors are never masked,
///    only "no answer at all";
///  * it reports whether the server was reachable, so the app can say "hors ligne".
class OfflineReadInterceptor extends Interceptor {
  OfflineReadInterceptor({required this.cache, required this.scope, this.onReachability});

  final OfflineCache cache;

  /// Whose data this is (user + business); null while nobody is signed in.
  final String? Function() scope;

  final void Function(bool reachable)? onReachability;

  bool _isReadable(RequestOptions o) {
    if (o.method != 'GET') return false;
    if (o.responseType == ResponseType.bytes || o.path.endsWith('/image')) return false;
    // '/me' must not swallow a future '/members…': a prefix matches on whole path segments.
    return _cacheablePrefixes.any((p) => o.path == p || o.path.startsWith('$p/'));
  }

  String? _scopeFor(RequestOptions o) => o.path == '/me' ? sessionScope : scope();

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    onReachability?.call(true);

    final options = response.requestOptions;
    final scopeKey = _scopeFor(options);
    final data = response.data;
    final storable = data is Map || data is List;
    // A free-text search is one of countless queries: not worth a cache slot (offline, it is
    // answered from the full list instead).
    if (scopeKey != null &&
        storable &&
        _isReadable(options) &&
        !options.queryParameters.containsKey('search')) {
      cache.put(scopeKey, cacheKeyFor(options), data).catchError((_) {});
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!isConnectionFailure(err)) {
      if (err.response != null) onReachability?.call(true);
      return handler.next(err);
    }

    onReachability?.call(false);

    final options = err.requestOptions;
    final scopeKey = _scopeFor(options);
    if (scopeKey == null || !_isReadable(options)) return handler.next(err);

    try {
      final entry =
          await cache.get(scopeKey, cacheKeyFor(options)) ?? await _derive(scopeKey, options);
      if (entry != null) {
        return handler.resolve(
          Response<Object?>(
            requestOptions: options,
            data: entry.data,
            statusCode: 200,
            extra: {'fromCache': true, 'cachedAt': entry.savedAt.toIso8601String()},
          ),
        );
      }
    } catch (_) {
      // A cache that fails must never turn a network error into something worse.
    }
    handler.next(err);
  }

  /// A filtered list nobody asked for before (a search, a category) is answered from the full
  /// list that was cached the last time the catalogue was open.
  Future<CachedEntry?> _derive(String scopeKey, RequestOptions o) async {
    if (o.path == '/products' || o.path == '/products/low-stock') {
      final base = await cache.get(scopeKey, 'GET /products?page=1&pageSize=100');
      final items = _itemsOf(base);
      if (base == null || items == null) return null;

      if (o.path == '/products/low-stock') {
        final low =
            items.where((p) {
              final threshold = _number(p['lowStockThreshold']);
              final stock = _number(p['currentStock']) ?? 0;
              return p['isActive'] != false && threshold != null && stock <= threshold;
            }).toList();
        return CachedEntry(data: low, savedAt: base.savedAt);
      }

      final q = o.queryParameters;
      // The cached list only holds active products: the inactive ones cannot be answered.
      if (q['isActive'] == false) return null;

      final search = (q['search'] as String? ?? '').trim().toLowerCase();
      final categoryId = q['categoryId'] as String?;
      final matches =
          items.where((p) {
            if (categoryId != null && p['categoryId'] != categoryId) return false;
            if (search.isEmpty) return true;
            return [
              'name',
              'sku',
              'barcode',
            ].any((field) => ((p[field] as String?) ?? '').toLowerCase().contains(search));
          }).toList();
      return CachedEntry(data: _page(matches), savedAt: base.savedAt);
    }

    if (o.path == '/customers') {
      final base = await cache.get(scopeKey, 'GET /customers?page=1&pageSize=100');
      final items = _itemsOf(base);
      if (base == null || items == null) return null;

      final search = (o.queryParameters['search'] as String? ?? '').trim().toLowerCase();
      final matches =
          items.where((c) {
            if (search.isEmpty) return true;
            return [
              'fullName',
              'phone',
            ].any((field) => ((c[field] as String?) ?? '').toLowerCase().contains(search));
          }).toList();
      return CachedEntry(data: _page(matches), savedAt: base.savedAt);
    }
    return null;
  }

  static List<Map<String, dynamic>>? _itemsOf(CachedEntry? entry) {
    final data = entry?.data;
    if (data is! Map || data['items'] is! List) return null;
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  static Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
    'items': items,
    'total': items.length,
    'page': 1,
    'pageSize': 100,
  };

  /// Prisma sends decimals as strings ("12.00").
  static double? _number(Object? value) {
    if (value == null) return null;
    return value is num ? value.toDouble() : double.tryParse(value.toString());
  }
}
