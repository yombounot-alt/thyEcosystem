import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/sales/offline/offline_warmup.dart';
import 'features/sales/offline/sales_sync_service.dart';

class ThyBusinessApp extends ConsumerWidget {
  const ThyBusinessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Keeps queued sales moving: sends them when the network is back, when the app returns to the
    // foreground and on a timer while something waits.
    ref.watch(salesSyncCoordinatorProvider);
    ref.watch(offlineWarmupProvider);

    return MaterialApp.router(
      title: 'THY Business',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // The whole product is in French: this also translates the framework's own strings
      // (back/menu tooltips, date pickers, copy/paste menus).
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
