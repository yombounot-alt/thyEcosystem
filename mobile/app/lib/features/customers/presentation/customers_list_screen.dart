import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/customers_providers.dart';
import '../data/customer_models.dart';

class CustomersListScreen extends ConsumerStatefulWidget {
  const CustomersListScreen({super.key});

  @override
  ConsumerState<CustomersListScreen> createState() => _CustomersListScreenState();
}

class _CustomersListScreenState extends ConsumerState<CustomersListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  bool _onlyIndebted = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersListProvider(_search));
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/customers/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Client'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Rechercher par nom ou téléphone',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: !_onlyIndebted,
                  onSelected: (_) => setState(() => _onlyIndebted = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Endettés'),
                  selected: _onlyIndebted,
                  onSelected: (_) => setState(() => _onlyIndebted = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: customers,
              onRetry: () => ref.invalidate(customersListProvider),
              data: (all) {
                final items = _onlyIndebted ? all.where((c) => c.hasDebt).toList() : all;
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    message:
                        _search.isEmpty && !_onlyIndebted
                            ? 'Aucun client pour le moment.\nAppuyez sur « Client » pour en ajouter un.'
                            : 'Aucun client ne correspond.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(customersListProvider);
                    await ref.read(customersListProvider(_search).future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder:
                        (context, i) => _CustomerTile(customer: items[i], currency: currency),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.currency});

  final Customer customer;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => context.push('/customers/${customer.id}'),
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Text(
          customer.fullName.characters.first.toUpperCase(),
          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(customer.fullName),
      subtitle: customer.phone == null ? null : Text(customer.phone!),
      trailing:
          customer.hasDebt
              ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(customer.currentBalance, currency: currency),
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                  ),
                  Text('doit', style: Theme.of(context).textTheme.bodySmall),
                ],
              )
              : null,
    );
  }
}
