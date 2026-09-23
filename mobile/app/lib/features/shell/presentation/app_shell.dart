import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../payments/application/payments_providers.dart';
import '../../sales/offline/offline_banner.dart';

class _Tab {
  const _Tab(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _tabs = [
  _Tab('/dashboard', 'Accueil', Icons.home_outlined, Icons.home),
  _Tab('/pos', 'Caisse', Icons.point_of_sale_outlined, Icons.point_of_sale),
  _Tab('/stock', 'Stock', Icons.inventory_2_outlined, Icons.inventory_2),
  _Tab('/more', 'Plus', Icons.menu, Icons.menu_open),
];

/// Bottom navigation shared by the four main tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _selectedIndex {
    final index = _tabs.indexWhere((tab) => location.startsWith(tab.path));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Payments customers declared and the owner has not checked yet (only the owner sees this).
    final toVerify = ref.watch(paymentsToVerifyProvider);

    return Scaffold(
      body: child,
      // The offline / pending-sales notice sits right above the tabs: visible on every main
      // screen without fighting each screen's own app bar for the top of the display.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (toVerify > 0) _ToVerifyBanner(count: toVerify),
          const OfflineBanner(),
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => context.go(_tabs[index].path),
            destinations: [
              for (final tab in _tabs)
                NavigationDestination(
                  icon: _withBadge(tab, Icon(tab.icon), toVerify),
                  selectedIcon: _withBadge(tab, Icon(tab.selectedIcon), toVerify),
                  label: tab.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The "Plus" tab holds the payments to verify: a small dot with their number.
Widget _withBadge(_Tab tab, Widget icon, int count) {
  if (tab.path != '/more' || count == 0) return icon;
  return Badge(label: Text('$count'), child: icon);
}

class _ToVerifyBanner extends StatelessWidget {
  const _ToVerifyBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE6EEFB),
      child: InkWell(
        onTap: () => context.push('/payments?status=submitted'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top, size: 20, color: Color(0xFF2F6FDE)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count > 1 ? '$count paiements à vérifier' : '1 paiement à vérifier',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
