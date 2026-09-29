import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/api/api_config.dart';
import 'core/config/app_environment.dart';
import 'core/observability/crash_reporting.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = AppEnvironment.current;

  // A build without its configuration (e.g. a staging/prod build without THY_API_BASE_URL) says so
  // on screen instead of crashing at the first request or talking to the wrong server.
  try {
    apiBaseUrl;
  } on StateError catch (e) {
    runApp(ConfigurationErrorApp(message: e.message));
    return;
  }

  await runWithCrashReporting(env, () => const ProviderScope(child: ThyApp()));
}

/// Shown instead of the app when the build is misconfigured (a developer's mistake, not a user's).
class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configuration de l\'application incomplète',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
