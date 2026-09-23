import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/customers_providers.dart';
import '../data/customer_models.dart';

/// Lets the cashier pick an existing customer or create one on the spot.
Future<Customer?> showCustomerPicker(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const CustomerPickerSheet(),
  );
}

class CustomerPickerSheet extends ConsumerStatefulWidget {
  const CustomerPickerSheet({super.key});

  @override
  ConsumerState<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<CustomerPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';

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

  Future<void> _createCustomer() async {
    final nameController = TextEditingController(text: _search);
    final phoneController = TextEditingController();
    final created = await showDialog<({String name, String phone})>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Nouveau client'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone (facultatif)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(dialogContext, (
                      name: nameController.text.trim(),
                      phone: phoneController.text.trim(),
                    )),
                child: const Text('Créer'),
              ),
            ],
          ),
    );
    if (created == null || created.name.length < 2 || !mounted) return;

    try {
      final customer = await ref
          .read(customersApiProvider)
          .create(fullName: created.name, phone: created.phone);
      ref.invalidate(customersListProvider);
      if (!mounted) return;
      Navigator.pop(context, customer);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersListProvider(_search));
    final currency = ref.watch(currencyProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Choisir un client', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  TextButton.icon(
                    onPressed: _createCustomer,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Nouveau'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Rechercher par nom ou téléphone',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView(
                value: customers,
                onRetry: () => ref.invalidate(customersListProvider),
                data: (items) {
                  if (items.isEmpty) {
                    return const EmptyState(
                      icon: Icons.people_outline,
                      message: 'Aucun client trouvé.\nUtilisez « Nouveau » pour en créer un.',
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final customer = items[i];
                      final owes = customer.currentBalance > 0;
                      return ListTile(
                        title: Text(customer.fullName),
                        subtitle: customer.phone == null ? null : Text(customer.phone!),
                        trailing:
                            owes
                                ? Text(
                                  'Doit ${formatMoney(customer.currentBalance, currency: currency)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                                : null,
                        onTap: () => Navigator.pop(context, customer),
                      );
                    },
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
