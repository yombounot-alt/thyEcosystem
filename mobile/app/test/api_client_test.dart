import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/api/api_client.dart';
import 'package:thy_app/core/api/api_exception.dart';
import 'package:thy_app/core/offline/offline_cache.dart';
import 'package:thy_app/core/storage/local_store.dart';

import 'fakes.dart';

/// A network we control: each request is answered (or fails) by [handler].
class _FakeNetwork implements HttpClientAdapter {
  _FakeNetwork(this.handler);

  Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}

  int count(String method, String path) =>
      seen.where((o) => o.method == method && o.path == path).length;
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

DioException _noNetwork(RequestOptions o) => DioException(
  requestOptions: o,
  type: DioExceptionType.connectionError,
  error: 'no route to host',
);

const _profile = {
  'id': 'user-1',
  'phone': '+224600000000',
  'fullName': 'Tamba Camara',
  'phoneVerified': true,
  'activeBusinessId': 'biz-1',
  'businesses': [
    {
      'id': 'biz-1',
      'name': 'Boutique Demo',
      'currency': 'GNF',
      'roleCode': 'OWNER',
      'permissions': ['sales:create'],
    },
  ],
};

Map<String, dynamic> _product(
  String id,
  String name, {
  String? categoryId,
  String? barcode,
  String stock = '10',
  String? threshold,
  bool active = true,
}) => {
  'id': id,
  'name': name,
  'categoryId': categoryId,
  'sku': null,
  'barcode': barcode,
  'isActive': active,
  'currentStock': stock,
  'lowStockThreshold': threshold,
};

Object _page(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'pageSize': 100,
};

void main() {
  _apiExceptionTests();

  late FakeTokenStorage tokens;

  setUp(() {
    tokens = FakeTokenStorage(access: 'old-access', refresh: 'old-refresh');
  });

  ApiClient clientWith(_FakeNetwork network) {
    final client = ApiClient(tokens);
    client.dio.httpClientAdapter = network;
    return client;
  }

  group('keeping people signed in', () {
    test('an expired access token on /auth/me is renewed and the request retried', () async {
      final network = _FakeNetwork((o) async {
        if (o.path == '/auth/refresh') {
          return _json({'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
        }
        if (o.headers['Authorization'] == 'Bearer old-access') return _json({}, status: 401);
        return _json(_profile);
      });

      final response = await clientWith(network).dio.get('/me');

      expect(response.statusCode, 200);
      expect(response.data['id'], 'user-1');
      expect(await tokens.readAccessToken(), 'new-access');
      expect(await tokens.readRefreshToken(), 'new-refresh');
      expect(network.count('POST', '/auth/refresh'), 1);
    });

    test('the renewed session keeps the active business', () async {
      String jwt(Map<String, Object?> claims) =>
          '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.'
          '${base64Url.encode(utf8.encode(jsonEncode(claims)))}.sig';
      tokens = FakeTokenStorage(
        access: jwt({'sub': 'user-1', 'bizId': 'biz-1'}),
        refresh: 'old-refresh',
      );
      Object? refreshBody;
      final network = _FakeNetwork((o) async {
        if (o.path == '/auth/refresh') {
          refreshBody = o.data;
          return _json({'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
        }
        return o.headers['Authorization'] == 'Bearer new-access'
            ? _json(_page([]))
            : _json({}, status: 401);
      });

      await clientWith(network).dio.get('/products');

      expect(refreshBody, {'refreshToken': 'old-refresh', 'businessId': 'biz-1'});
    });

    test('with no active business, none is asked for when renewing', () async {
      Object? refreshBody;
      final network = _FakeNetwork((o) async {
        if (o.path == '/auth/refresh') {
          refreshBody = o.data;
          return _json({'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
        }
        return o.headers['Authorization'] == 'Bearer new-access'
            ? _json(_page([]))
            : _json({}, status: 401);
      });

      await clientWith(network).dio.get('/products');

      expect(refreshBody, {'refreshToken': 'old-refresh'});
    });

    test('a refresh token the server refuses ends the session', () async {
      final network = _FakeNetwork((o) async => _json({'message': 'refus'}, status: 401));

      await expectLater(
        clientWith(network).dio.get('/products'),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 401)),
      );

      expect(await tokens.readAccessToken(), isNull);
      expect(await tokens.readRefreshToken(), isNull);
    });

    test('a refresh that cannot reach the server does NOT end the session', () async {
      final network = _FakeNetwork((o) async {
        if (o.path == '/auth/refresh') throw _noNetwork(o);
        return _json({}, status: 401);
      });

      await expectLater(
        clientWith(network).dio.get('/products'),
        throwsA(
          isA<DioException>().having((e) => isConnectionFailure(e), 'is a network failure', true),
        ),
      );

      expect(await tokens.readAccessToken(), 'old-access');
      expect(await tokens.readRefreshToken(), 'old-refresh');
    });

    test('a server error while refreshing does NOT end the session either', () async {
      final network = _FakeNetwork((o) async {
        if (o.path == '/auth/refresh') return _json({'message': 'oups'}, status: 503);
        return _json({}, status: 401);
      });

      await expectLater(clientWith(network).dio.get('/products'), throwsA(isA<DioException>()));

      expect(await tokens.readRefreshToken(), 'old-refresh');
    });

    test('a wrong sign-in code is not mistaken for an expired session', () async {
      final network = _FakeNetwork(
        (o) async => _json({
          'error': {'code': 'OTP_INVALID', 'message': 'Code invalide ou expiré'},
        }, status: 401),
      );

      await expectLater(
        clientWith(network).dio.post('/auth/otp/verify', data: {'phone': 'x', 'code': '000000'}),
        throwsA(isA<DioException>()),
      );

      expect(network.count('POST', '/auth/refresh'), 0);
    });

    test('concurrent 401s share a single refresh', () async {
      var refreshed = false;
      final network = _FakeNetwork((o) async {
        if (o.path == '/auth/refresh') {
          refreshed = true;
          return _json({'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
        }
        return refreshed ? _json(_page([])) : _json({}, status: 401);
      });
      final dio = clientWith(network).dio;

      await Future.wait([dio.get('/products'), dio.get('/customers'), dio.get('/categories')]);

      expect(network.count('POST', '/auth/refresh'), 1);
    });
  });

  group('offline reads', () {
    late MemoryLocalStore store;
    late OfflineCache cache;
    String? scope;
    late List<bool> reachability;

    ApiClient offlineClient(_FakeNetwork network) {
      final client = ApiClient(
        tokens,
        cache: cache,
        scope: () => scope,
        onReachability: reachability.add,
      );
      client.dio.httpClientAdapter = network;
      return client;
    }

    /// Lets the fire-and-forget cache writes finish.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() {
      store = MemoryLocalStore();
      cache = OfflineCache(store);
      scope = 'user-1:biz-1';
      reachability = [];
    });

    test('the last good answer is served when the server cannot be reached', () async {
      var online = true;
      final network = _FakeNetwork((o) async {
        if (!online) throw _noNetwork(o);
        return _json([
          {'id': 'c1', 'name': 'Boissons'},
        ]);
      });
      final dio = offlineClient(network).dio;

      await dio.get('/categories');
      await settle();
      online = false;
      final offline = await dio.get('/categories');

      expect(offline.data, [
        {'id': 'c1', 'name': 'Boissons'},
      ]);
      expect(offline.extra['fromCache'], isTrue);
      expect(DateTime.parse(offline.extra['cachedAt'] as String), isA<DateTime>());
    });

    test('the profile is available offline at start-up, before anyone is "in scope"', () async {
      var online = true;
      final network = _FakeNetwork((o) async {
        if (!online) throw _noNetwork(o);
        return _json(_profile);
      });
      scope = null; // a cold start: the scope is only known once the profile has been read
      final dio = offlineClient(network).dio;

      await dio.get('/me');
      await settle();
      online = false;
      final offline = await dio.get('/me');

      expect(offline.data['fullName'], 'Tamba Camara');
      expect(offline.extra['fromCache'], isTrue);
    });

    test('an error answer from the server is never replaced by cached data', () async {
      var failing = false;
      final network = _FakeNetwork((o) async {
        if (failing) return _json({'message': 'boum'}, status: 500);
        return _json(_page([_product('p1', 'Eau')]));
      });
      final dio = offlineClient(network).dio;

      await dio.get('/products', queryParameters: {'page': 1, 'pageSize': 100});
      await settle();
      failing = true;

      await expectLater(
        dio.get('/products', queryParameters: {'page': 1, 'pageSize': 100}),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 500)),
      );
    });

    test('nothing is cached (or served) while nobody is signed in', () async {
      var online = true;
      final network = _FakeNetwork((o) async {
        if (!online) throw _noNetwork(o);
        return _json([]);
      });
      scope = null;
      final dio = offlineClient(network).dio;

      await dio.get('/categories');
      await settle();
      online = false;

      await expectLater(dio.get('/categories'), throwsA(isA<DioException>()));
    });

    test("one business's cached data is never served to another", () async {
      var online = true;
      final network = _FakeNetwork((o) async {
        if (!online) throw _noNetwork(o);
        return _json([
          {'id': 'c1', 'name': 'Boissons'},
        ]);
      });
      final dio = offlineClient(network).dio;

      await dio.get('/categories');
      await settle();
      online = false;
      scope = 'user-2:biz-2';

      await expectLater(dio.get('/categories'), throwsA(isA<DioException>()));
    });

    test('writes are never answered from the cache', () async {
      final network = _FakeNetwork((o) async => throw _noNetwork(o));

      await expectLater(
        offlineClient(network).dio.post('/sales', data: {'items': []}),
        throwsA(isA<DioException>().having((e) => isConnectionFailure(e), 'network', true)),
      );
    });

    test('photos (binary answers) are not cached', () async {
      final network = _FakeNetwork((o) async {
        return ResponseBody.fromBytes(
          [1, 2, 3],
          200,
          headers: {
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
      });
      final dio = offlineClient(network).dio;

      await dio.get<List<int>>(
        '/products/p1/image',
        options: Options(responseType: ResponseType.bytes),
      );
      await settle();

      expect(store.values.keys.where((k) => k.startsWith('offline_cache:entry:')), isEmpty);
    });

    test('says whether the server could be reached', () async {
      var mode = 'ok';
      final network = _FakeNetwork((o) async {
        if (mode == 'down') throw _noNetwork(o);
        if (mode == 'error') return _json({'message': 'non'}, status: 400);
        return _json([]);
      });
      final dio = offlineClient(network).dio;

      await dio.get('/categories');
      mode = 'down';
      await dio.get('/categories').catchError((_) => Response(requestOptions: RequestOptions()));
      mode = 'error';
      await dio
          .post('/sales', data: {})
          .catchError((_) => Response(requestOptions: RequestOptions()));

      // reachable, then unreachable, then reachable again (a 400 is still an answer).
      expect(reachability, [true, false, true]);
    });

    group('searching the catalogue offline', () {
      late _FakeNetwork network;
      late Dio dio;
      var online = true;

      setUp(() async {
        online = true;
        network = _FakeNetwork((o) async {
          if (!online) throw _noNetwork(o);
          return _json(
            _page([
              _product('p1', 'Eau minérale 1.5L', categoryId: 'boissons', barcode: '6001234000011'),
              _product('p2', 'Savon de toilette', categoryId: 'hygiene', barcode: '6001234000066'),
              _product(
                'p3',
                'Sucre en poudre',
                categoryId: 'alimentaire',
                stock: '4',
                threshold: '10',
              ),
              _product('p4', 'Riz', categoryId: 'alimentaire', stock: '30', threshold: '3'),
            ]),
          );
        });
        dio = offlineClient(network).dio;
        // Opening the catalogue once, online, is what fills the cache.
        await dio.get('/products', queryParameters: {'page': 1, 'pageSize': 100});
        await settle();
        online = false;
      });

      Future<List<String>> names(Map<String, dynamic> query) async {
        final r = await dio.get(
          '/products',
          queryParameters: {...query, 'page': 1, 'pageSize': 100},
        );
        return [for (final p in r.data['items'] as List) p['name'] as String];
      }

      test('by name, ignoring the case', () async {
        expect(await names({'search': 'SAV'}), ['Savon de toilette']);
      });

      test('by barcode (what a scanner types)', () async {
        expect(await names({'search': '6001234000011'}), ['Eau minérale 1.5L']);
      });

      test('by category', () async {
        expect(await names({'categoryId': 'alimentaire'}), ['Sucre en poudre', 'Riz']);
      });

      test('an unknown code finds nothing rather than failing', () async {
        expect(await names({'search': '9999999999999'}), isEmpty);
      });

      test('the low-stock list is worked out from the cached catalogue', () async {
        final r = await dio.get('/products/low-stock');
        expect([for (final p in r.data as List) p['name']], ['Sucre en poudre']);
      });

      test(
        'inactive products cannot be listed offline (the cache only holds active ones)',
        () async {
          await expectLater(
            dio.get('/products', queryParameters: {'isActive': false, 'page': 1, 'pageSize': 100}),
            throwsA(isA<DioException>()),
          );
        },
      );
    });

    test('customers can be searched offline too (to sell on credit)', () async {
      var online = true;
      final network = _FakeNetwork((o) async {
        if (!online) throw _noNetwork(o);
        return _json(
          _page([
            {'id': 'c1', 'fullName': 'Mamadou Diallo', 'phone': '+224655555555'},
            {'id': 'c2', 'fullName': 'Aïssatou Bah', 'phone': '+224622000000'},
          ]),
        );
      });
      final dio = offlineClient(network).dio;
      await dio.get('/customers', queryParameters: {'page': 1, 'pageSize': 100});
      await settle();
      online = false;

      final byName = await dio.get(
        '/customers',
        queryParameters: {'search': 'mama', 'page': 1, 'pageSize': 100},
      );
      final byPhone = await dio.get(
        '/customers',
        queryParameters: {'search': '6220', 'page': 1, 'pageSize': 100},
      );

      expect([for (final c in byName.data['items'] as List) c['fullName']], ['Mamadou Diallo']);
      expect([for (final c in byPhone.data['items'] as List) c['fullName']], ['Aïssatou Bah']);
    });
  });

  group('OfflineCache', () {
    test('keeps only the most recent entries', () async {
      final store = MemoryLocalStore();
      final cache = OfflineCache(store, maxEntries: 3);

      for (var i = 1; i <= 5; i++) {
        await cache.put('s', 'key$i', {'n': i});
      }

      expect(await cache.get('s', 'key1'), isNull);
      expect(await cache.get('s', 'key2'), isNull);
      expect((await cache.get('s', 'key5'))!.data, {'n': 5});
      expect(store.values.keys.where((k) => k.startsWith('offline_cache:entry:')), hasLength(3));
    });

    test('rewriting an entry refreshes it instead of duplicating it', () async {
      final cache = OfflineCache(MemoryLocalStore(), maxEntries: 2);

      await cache.put('s', 'a', 1);
      await cache.put('s', 'b', 2);
      await cache.put('s', 'a', 3); // a is now the freshest
      await cache.put('s', 'c', 4); // evicts b, the oldest

      expect((await cache.get('s', 'a'))!.data, 3);
      expect(await cache.get('s', 'b'), isNull);
      expect((await cache.get('s', 'c'))!.data, 4);
    });

    test('concurrent writes do not lose each other', () async {
      final cache = OfflineCache(MemoryLocalStore(), maxEntries: 50);

      await Future.wait([for (var i = 0; i < 20; i++) cache.put('s', 'k$i', i)]);

      for (var i = 0; i < 20; i++) {
        expect((await cache.get('s', 'k$i'))!.data, i);
      }
    });

    test('clear forgets everything, for every scope', () async {
      final store = MemoryLocalStore();
      final cache = OfflineCache(store);
      await cache.put('user-1:biz-1', 'a', 1);
      await cache.put('user-2:biz-2', 'b', 2);

      await cache.clear();

      expect(await cache.get('user-1:biz-1', 'a'), isNull);
      expect(await cache.get('user-2:biz-2', 'b'), isNull);
      expect(store.values, isEmpty);
    });

    test('a damaged entry reads as missing', () async {
      final store = MemoryLocalStore();
      final cache = OfflineCache(store);
      await cache.put('s', 'a', 1);
      final key = store.values.keys.firstWhere((k) => k.startsWith('offline_cache:entry:'));
      store.values[key] = '{not json';

      expect(await cache.get('s', 'a'), isNull);
    });
  });
}

void _apiExceptionTests() {
  group('the server error envelope', () {
    DioException failing(Object? body, {int status = 400}) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );

    test('the message and the stable code are read from { error: { … } }', () {
      final e = ApiException.fromDioError(
        failing({
          'error': {'code': 'OTP_INVALID', 'message': 'Code invalide ou expiré', 'requestId': 'r'},
        }, status: 422),
      );
      expect(e.message, 'Code invalide ou expiré');
      expect(e.code, 'OTP_INVALID');
      expect(e.statusCode, 422);
    });

    test('validation details are listed, one per line', () {
      final e = ApiException.fromDioError(
        failing({
          'error': {
            'code': 'VALIDATION_FAILED',
            'message': 'Données invalides',
            'details': ['name must be a string', 'salePrice must be a number'],
          },
        }),
      );
      expect(e.message, 'name must be a string\nsalePrice must be a number');
    });

    test('a body that is not the envelope falls back to something readable', () {
      final e = ApiException.fromDioError(failing('<html>Bad gateway</html>', status: 502));
      expect(e.message, isNotEmpty);
      expect(e.statusCode, 502);
    });
  });
}
