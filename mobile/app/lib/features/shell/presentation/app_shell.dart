import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/modules/app_module.dart';
import '../../../core/modules/module_registry.dart';
import '../../sales/offline/offline_banner.dart';

/// Bottom navigation shared by the main tabs. It knows no module: tabs, banners and the badge of
/// "Plus" come from the installed modules (core/modules/module_registry.dart).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(appModulesProvider);
    final tabs = ref.watch(navigationProvider).tabs;
    final index = tabs.indexWhere((tab) => location.startsWith(tab.path));
    // Things waiting in the modules' menus (e.g. payments to verify): a number on "Plus".
    final moreBadge = modules.fold<int>(0, (sum, m) => sum + m.moreBadge(ref));

    Widget withBadge(ModuleTab tab, Widget icon) {
      if (tab.path != '/more' || moreBadge == 0) return icon;
      return Badge(label: Text('$moreBadge'), child: icon);
    }

    return Scaffold(
      body: child,
      // Notices sit right above the tabs: visible on every main screen without fighting each
      // screen's own app bar for the top of the display.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final module in modules)
            if (module.shellBanner() case final banner?) banner,
          const OfflineBanner(),
          NavigationBar(
            selectedIndex: index < 0 ? 0 : index,
            onDestinationSelected: (i) => context.go(tabs[i].path),
            destinations: [
              for (final tab in tabs)
                NavigationDestination(
                  icon: withBadge(tab, Icon(tab.icon)),
                  selectedIcon: withBadge(tab, Icon(tab.selectedIcon)),
                  label: tab.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
