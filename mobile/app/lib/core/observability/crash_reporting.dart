import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_environment.dart';

/// Sentry DSN, given at build time (`--dart-define=THY_SENTRY_DSN=…`). Empty: nothing is reported.
const String sentryDsn = String.fromEnvironment('THY_SENTRY_DSN');

/// Keeps only technical data before an event leaves the phone — allow-list, like the backend
/// (backend/src/kernel/observability/scrub.ts): request method only, user id only, no breadcrumbs
/// (they carry URLs, typed text and navigation), no server/device name.
SentryEvent scrubSentryEvent(SentryEvent event) {
  final request = event.request;
  final user = event.user;
  return event.copyWith(
    request: request == null ? null : SentryRequest(method: request.method),
    user: user?.id == null ? null : SentryUser(id: user!.id),
    breadcrumbs: const [],
    serverName: '',
  );
}

/// Starts the app with crash reporting when a DSN was given at build time, or directly otherwise.
Future<void> runWithCrashReporting(AppEnvironment env, Widget Function() app) async {
  if (sentryDsn.isEmpty) {
    runApp(app());
    return;
  }
  await SentryFlutter.init((options) {
    options
      ..dsn = sentryDsn
      ..environment = env.name
      ..sendDefaultPii = false
      ..attachScreenshot = false
      // Errors only: no performance tracing from the phone for now.
      ..tracesSampleRate = 0
      ..beforeSend = (event, hint) => scrubSentryEvent(event);
  }, appRunner: () => runApp(app()));
}
