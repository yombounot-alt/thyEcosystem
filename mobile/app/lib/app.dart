import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_design_system/thy_design_system.dart';

import 'navigation/app_router.dart';
import 'l10n/app_localizations.dart';
import 'features/sales/offline/offline_warmup.dart';
import 'features/sales/offline/sales_sync_service.dart';

class ThyApp extends ConsumerWidget {
  const ThyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Keeps queued sales moving: sends them when the network is back, when the app returns to the
    // foreground and on a timer while something waits.
    ref.watch(salesSyncCoordinatorProvider);
    ref.watch(offlineWarmupProvider);

    return MaterialApp.router(
      title: 'THY',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Suit le réglage du téléphone (clair/sombre).
      themeMode: ThemeMode.system,
      // French only for now: the English translation (lib/l10n/app_en.arb) covers a few screens so
      // far, and a half-English app would be worse than an all-French one. Once every screen reads
      // its texts from AppLocalizations, supportedLocales becomes AppLocalizations.supportedLocales
      // and the phone's language is followed. The same delegates translate the framework's own
      // texts (tooltips, date pickers, copy/paste menus).
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    );
  }
}
