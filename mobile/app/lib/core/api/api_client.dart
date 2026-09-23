import 'dart:async';

import 'package:dio/dio.dart';

import '../offline/offline_cache.dart';
import '../offline/offline_read_interceptor.dart';
import '../storage/token_storage.dart';
import 'api_config.dart';
import 'jwt_claims.dart';

/// What happened when the session was renewed after a 401.
class _Refresh {
  const _Refresh.done(this.accessToken) : rejected = false;
  const _Refresh.rejected() : accessToken = null, rejected = true;

  /// The server could not be reached (or failed): the session may well still be valid.
  const _Refresh.unreachable() : accessToken = null, rejected = false;

  final String? accessToken;

  /// The server answered and said the refresh token is no good: the session is really over.
  final bool rejected;
}

/// Dio instance wired with automatic bearer-token attachment and a single-flight
/// 401 -> refresh -> retry-once flow, so callers never have to think about tokens.
///
/// A missing network is never mistaken for an ended session: tokens are only discarded when the
/// server itself refuses the refresh token. When a [cache] is given, reads fall back to it while
/// the server is unreachable (see [OfflineReadInterceptor]).
class ApiClient {
  ApiClient(
    this._tokenStorage, {
    OfflineCache? cache,
    String? Function()? scope,
    void Function(bool reachable)? onReachability,
  }) {
    dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
    if (cache != null) {
      dio.interceptors.add(
        OfflineReadInterceptor(
          cache: cache,
          scope: scope ?? () => null,
          onReachability: onReachability,
        ),
      );
    }
  }

  late final Dio dio;
  final TokenStorage _tokenStorage;
  Completer<_Refresh>? _refreshCompleter;

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _tokenStorage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  /// Public routes: a 401 there means "wrong credentials" (or a refused refresh token), not "your
  /// access token expired", so it must not trigger a refresh. `/auth/me` is NOT one of them — it
  /// needs a valid access token like any other route, and renewing it is what keeps someone signed
  /// in when they reopen the app after the 15 minutes an access token lives.
  static const _publicAuthPaths = {
    '/auth/otp/request',
    '/auth/otp/verify',
    '/auth/refresh',
    '/auth/logout',
  };

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final isPublicAuthEndpoint = _publicAuthPaths.contains(error.requestOptions.path);

    if (error.response?.statusCode == 401 && !isPublicAuthEndpoint) {
      final refresh = await _refreshAccessToken();
      final newAccessToken = refresh.accessToken;
      if (newAccessToken != null) {
        try {
          final response = await dio.fetch(error.requestOptions);
          return handler.resolve(response);
        } on DioException catch (retryError) {
          return handler.next(retryError);
        }
      }
      if (refresh.rejected) {
        await _tokenStorage.clear();
      } else {
        // Could not reach the server to renew the session: report a network problem (which the
        // app handles gracefully) rather than a 401 (which would look like a lost session).
        return handler.next(
          DioException(
            requestOptions: error.requestOptions,
            type: DioExceptionType.connectionError,
            error: error,
          ),
        );
      }
    }

    handler.next(error);
  }

  /// Single-flight: concurrent 401s while a refresh is already in progress all
  /// await the same result instead of racing separate /auth/refresh calls.
  Future<_Refresh> _refreshAccessToken() {
    final existing = _refreshCompleter;
    if (existing != null) return existing.future;

    final completer = Completer<_Refresh>();
    _refreshCompleter = completer;
    _performRefresh(completer);
    return completer.future;
  }

  Future<void> _performRefresh(Completer<_Refresh> completer) async {
    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken == null) {
        completer.complete(const _Refresh.rejected());
        return;
      }

      // Hand the active business back so the renewed token keeps working on the same business.
      final businessId = activeBusinessIdFromToken(await _tokenStorage.readAccessToken());
      final response = await dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken, if (businessId != null) 'businessId': businessId},
      );
      final accessToken = response.data['accessToken'] as String;
      final newRefreshToken = response.data['refreshToken'] as String;
      await _tokenStorage.saveTokens(accessToken: accessToken, refreshToken: newRefreshToken);
      completer.complete(_Refresh.done(accessToken));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Only an explicit refusal ends the session; no answer, or a server having a bad day
      // (5xx), does not.
      final refused = status == 400 || status == 401 || status == 403;
      completer.complete(refused ? const _Refresh.rejected() : const _Refresh.unreachable());
    } catch (_) {
      completer.complete(const _Refresh.unreachable());
    } finally {
      _refreshCompleter = null;
    }
  }
}
