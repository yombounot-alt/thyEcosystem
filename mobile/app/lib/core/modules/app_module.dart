import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A main tab a module contributes to the bottom navigation.
class ModuleTab {
  const ModuleTab({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() screen;
}

/// A business module of the super app (Business today; Marketplace, Services… later).
///
/// The shell knows no module: it assembles what each one declares — its home, its tabs, its routes,
/// its section of the "Plus" menu, an optional banner above the tabs and the badge of the "Plus" tab
/// (docs/blueprint/02-architecture.md §7, `ModuleRegistry` / `NavigationPolicy`).
abstract class AppModule {
  const AppModule();

  /// Stable identifier (`business`, `marketplace`…).
  String get id;

  /// Screen of the "Accueil" tab when this module is the main one.
  ModuleTab get home;

  /// Main tabs, between "Accueil" and "Plus".
  List<ModuleTab> get tabs;

  /// Every other route of the module (full screens pushed over the shell).
  List<RouteBase> get routes;

  /// The module's entries in the "Plus" menu.
  Widget moreSection();

  /// Shown above the tabs on every main screen (e.g. payments waiting to be checked), or nothing.
  Widget? shellBanner() => null;

  /// Number shown on the "Plus" tab (things waiting in this module's menu), 0 for none.
  int moreBadge(WidgetRef ref) => 0;
}

/// Navigation policy: at most this many module tabs between "Accueil" and "Plus" (5 slots in all).
const maxModuleTabs = 3;
