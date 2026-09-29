import 'package:flutter/services.dart' show appFlavor;

/// Where this build runs. Chosen by the Android flavor (`flutter run --flavor dev|staging|prod`,
/// see android/app/build.gradle.kts); builds without a flavor (web, tests) are `dev`.
enum AppEnvironment {
  dev,
  staging,
  prod;

  static AppEnvironment fromFlavor(String? flavor) => switch (flavor) {
    'prod' => AppEnvironment.prod,
    'staging' => AppEnvironment.staging,
    _ => AppEnvironment.dev,
  };

  static final AppEnvironment current = fromFlavor(appFlavor);

  bool get isProd => this == AppEnvironment.prod;
}

/// API base URL override, given at build time: `--dart-define=THY_API_BASE_URL=https://…/api/v1`.
const String _apiBaseUrlOverride = String.fromEnvironment('THY_API_BASE_URL');

/// Local backend (backend/, port 3300). From the Android emulator, 10.0.2.2 is the host machine;
/// on a physical phone, pass the machine's LAN address with THY_API_BASE_URL instead.
const String _devApiBaseUrl = 'http://10.0.2.2:3300/api/v1';

/// The API this build talks to. Staging and production have NO default: a build without its URL
/// refuses to start (clear message) instead of silently talking to the wrong server.
String resolveApiBaseUrl(AppEnvironment env, {String override = _apiBaseUrlOverride}) {
  if (override.isNotEmpty) {
    if (env != AppEnvironment.dev && !override.startsWith('https://')) {
      throw StateError('THY_API_BASE_URL doit être en https pour ${env.name} (reçu : $override).');
    }
    return override;
  }
  if (env == AppEnvironment.dev) return _devApiBaseUrl;
  throw StateError(
    'THY_API_BASE_URL manquant pour ${env.name} : '
    'flutter build … --flavor ${env.name} --dart-define=THY_API_BASE_URL=https://…/api/v1',
  );
}
