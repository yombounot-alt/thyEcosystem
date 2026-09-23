import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/dashboard_providers.dart';
import '../data/dashboard_models.dart';
import 'sales_bar_chart.dart';

/// "Accueil": the day at a glance — sales, profit, alerts, 7-day chart, best sellers.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardPeriod _period = DashboardPeriod.today;

  Future<void> _refresh() async {
    invalidateDashboard(ref);
    await ref.read(dashboardSummaryProvider(_period).future);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    final business = ref.watch(activeBusinessProvider);
    final currency = ref.watch(currencyProvider);

    // The router only sends us here once AuthStatus.authenticated is reached,
    // which always carries a profile — but stay defensive rather than assume.
    if (profile == null || business == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final summary = ref.watch(dashboardSummaryProvider(_period));
    final chart = ref.watch(salesChartProvider);
    final topProducts = ref.watch(topProductsProvider(_period));
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(business.name)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Bonjour, ${profile.fullName?.split(' ').first ?? ''} 👋',
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => context.go('/pos'),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Nouvelle vente'),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final period in DashboardPeriod.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(period.label),
                        selected: _period == period,
                        onSelected: (_) => setState(() => _period = period),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AsyncView(
              value: summary,
              onRetry: () => ref.invalidate(dashboardSummaryProvider),
              data: (s) => _SummarySection(summary: s, currency: currency),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: '7 derniers jours',
              child: AsyncView(
                value: chart,
                onRetry: () => ref.invalidate(salesChartProvider),
                data: (points) => SalesBarChart(points: points, currency: currency),
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Produits populaires',
              child: AsyncView(
                value: topProducts,
                onRetry: () => ref.invalidate(topProductsProvider),
                data: (items) {
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Aucune vente sur cette période.'),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _TopProductRow(rank: i + 1, product: items[i], currency: currency),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary, required this.currency});

  final DashboardSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final profit = summary.profit;
    final cogs = summary.cogs;
    final profitColor = (profit ?? 0) < 0 ? AppColors.danger : AppColors.success;
    // Profit is only shown to those allowed to see it (server-side permission).
    final kpis = <Widget>[
      _KpiCard(
        label: "Chiffre d'affaires",
        value: formatMoney(summary.revenue, currency: currency),
        icon: Icons.trending_up,
      ),
      if (profit != null)
        _KpiCard(
          label: 'Bénéfice estimé',
          value: formatMoney(profit, currency: currency),
          icon: Icons.savings_outlined,
          color: profitColor,
        ),
      _KpiCard(
        label: 'Dépenses',
        value: formatMoney(summary.expensesTotal, currency: currency),
        icon: Icons.receipt_long_outlined,
      ),
      _KpiCard(
        label: 'Commandes',
        value: '${summary.ordersCount}',
        icon: Icons.shopping_bag_outlined,
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < kpis.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: kpis[i]),
              const SizedBox(width: 12),
              Expanded(child: i + 1 < kpis.length ? kpis[i + 1] : const SizedBox.shrink()),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _SectionCard(title: 'Alertes', child: _Alerts(summary: summary, currency: currency)),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Détail financier',
          child: Column(
            children: [
              _FinanceRow("Chiffre d'affaires", formatMoney(summary.revenue, currency: currency)),
              if (cogs != null) _FinanceRow('Coût des marchandises', _deduction(cogs, currency)),
              _FinanceRow('Dépenses', _deduction(summary.expensesTotal, currency)),
              if (profit != null) ...[
                const Divider(),
                _FinanceRow(
                  'Bénéfice estimé',
                  formatMoney(profit, currency: currency),
                  bold: true,
                  color: profitColor,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// A cost shown as a deduction ("−9 000 GNF") — but a plain "0 GNF" rather than "−0 GNF".
  static String _deduction(num amount, String currency) =>
      amount.round() == 0
          ? formatMoney(0, currency: currency)
          : '−${formatMoney(amount, currency: currency)}';
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.icon, this.color});

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color ?? AppColors.primary),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _FinanceRow extends StatelessWidget {
  const _FinanceRow(this.label, this.value, {this.bold = false, this.color});

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      fontSize: bold ? 16 : 14,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({required this.summary, required this.currency});

  final DashboardSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (summary.lowStockCount > 0)
        _AlertRow(
          icon: Icons.inventory_2_outlined,
          color: AppColors.danger,
          text:
              '${summary.lowStockCount} produit${summary.lowStockCount > 1 ? 's' : ''} en stock faible',
          onTap: () => context.go('/stock'),
        ),
      if (summary.overdueCreditsCount > 0)
        _AlertRow(
          icon: Icons.schedule,
          color: AppColors.warning,
          text:
              '${summary.overdueCreditsCount} crédit${summary.overdueCreditsCount > 1 ? 's' : ''} client en retard',
          onTap: () => context.push('/credits'),
        ),
      if (summary.outstandingCredits > 0)
        _AlertRow(
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.primary,
          text:
              'Créances en cours : ${formatMoney(summary.outstandingCredits, currency: currency)}',
          onTap: () => context.push('/credits'),
        ),
    ];

    if (rows.isEmpty) {
      return const Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.success),
          SizedBox(width: 8),
          Text('Aucune alerte pour le moment.'),
        ],
      );
    }
    return Column(children: rows);
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.icon,
    required this.color,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _TopProductRow extends StatelessWidget {
  const _TopProductRow({required this.rank, required this.product, required this.currency});

  final int rank;
  final TopProduct product;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Text(
              '$rank',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name),
                Text(
                  '${formatQuantity(product.quantity)} vendu${product.quantity > 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            formatMoney(product.revenue, currency: currency),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
