import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:thy_app/core/config/app_environment.dart';
import 'package:thy_app/core/observability/crash_reporting.dart';

void main() {
  group('environment (Android flavor)', () {
    test('the flavor chooses the environment; no flavor (web, tests) is dev', () {
      expect(AppEnvironment.fromFlavor('prod'), AppEnvironment.prod);
      expect(AppEnvironment.fromFlavor('staging'), AppEnvironment.staging);
      expect(AppEnvironment.fromFlavor('dev'), AppEnvironment.dev);
      expect(AppEnvironment.fromFlavor(null), AppEnvironment.dev);
      expect(AppEnvironment.current, AppEnvironment.dev);
    });

    test('dev talks to the local backend unless told otherwise', () {
      expect(resolveApiBaseUrl(AppEnvironment.dev, override: ''), 'http://10.0.2.2:3300/api/v1');
      expect(
        resolveApiBaseUrl(AppEnvironment.dev, override: 'http://192.168.1.20:3300/api/v1'),
        'http://192.168.1.20:3300/api/v1',
      );
    });

    test('staging and production have no default URL: the build must give one', () {
      for (final env in [AppEnvironment.staging, AppEnvironment.prod]) {
        expect(
          () => resolveApiBaseUrl(env, override: ''),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', contains('THY_API_BASE_URL')),
          ),
        );
      }
    });

    test('staging and production refuse plain http', () {
      expect(
        () => resolveApiBaseUrl(AppEnvironment.prod, override: 'http://api.thy.test/api/v1'),
        throwsStateError,
      );
      expect(
        resolveApiBaseUrl(AppEnvironment.prod, override: 'https://api.thy.test/api/v1'),
        'https://api.thy.test/api/v1',
      );
    });
  });

  group('crash reports leave the phone without personal data', () {
    test('only the request method and the user id are kept; breadcrumbs are dropped', () {
      final event = SentryEvent(
        request: SentryRequest(
          method: 'POST',
          url: 'https://api.thy.test/api/v1/auth/otp/verify?phone=%2B224620000000',
          headers: {'Authorization': 'Bearer secret'},
          data: {'phone': '+224620000000', 'code': '123456'},
        ),
        user: SentryUser(id: 'u-1', ipAddress: '41.1.2.3', email: 'a@b.c'),
        breadcrumbs: [Breadcrumb(message: 'typed +224620000000')],
        serverName: 'phone-of-awa',
      );
      final clean = scrubSentryEvent(event);
      expect(clean.request?.method, 'POST');
      expect(clean.request?.url, isNull);
      expect(clean.request?.headers, isEmpty);
      expect(clean.request?.data, isNull);
      expect(clean.user?.id, 'u-1');
      expect(clean.user?.ipAddress, isNull);
      expect(clean.user?.email, isNull);
      expect(clean.breadcrumbs, isEmpty);
      expect(clean.serverName, isEmpty);
    });

    test('an event without request or user stays without them', () {
      final clean = scrubSentryEvent(SentryEvent(message: SentryMessage('boom')));
      expect(clean.request, isNull);
      expect(clean.user, isNull);
    });
  });
}
