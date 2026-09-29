import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_core/thy_core.dart';

import '../modules/business/business_module.dart';

/// Modules installed in this build, the main one first (its home is the "Accueil" tab). Adding
/// Marketplace or Services later = adding it here; the shell, the router and "Plus" follow.
final appModulesProvider = Provider<List<AppModule>>((ref) => const [BusinessModule()]);

/// The bottom navigation: "Accueil", the modules' tabs (at most [maxModuleTabs]), "Plus".
class Navigation {
  const Navigation({required this.tabs});

  /// Every main tab, in order, "Plus" included.
  final List<ModuleTab> tabs;
}

const _moreTab = ModuleTab(
  path: '/more',
  label: 'Plus',
  icon: Icons.menu,
  selectedIcon: Icons.menu_open,
  screen: _noScreen,
);

// "Plus" is built by the router itself (MoreScreen); the tab only carries its place and icon.
Widget _noScreen() => const SizedBox.shrink();

/// Builds the navigation policy from the installed modules.
Navigation buildNavigation(List<AppModule> modules) {
  if (modules.isEmpty) throw StateError('Aucun module installé');
  final moduleTabs = [for (final m in modules) ...m.tabs];
  if (moduleTabs.length > maxModuleTabs) {
    throw StateError(
      '${moduleTabs.length} onglets de modules pour $maxModuleTabs emplacements : '
      'la politique de navigation doit choisir lesquels afficher.',
    );
  }
  return Navigation(tabs: [modules.first.home, ...moduleTabs, _moreTab]);
}

final navigationProvider = Provider<Navigation>(
  (ref) => buildNavigation(ref.watch(appModulesProvider)),
);
