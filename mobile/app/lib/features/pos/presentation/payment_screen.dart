import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/json_helpers.dart';
import '../../../core/api/request_id.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_selectors.dart';
import '../../customers/data/customer_models.dart';
import '../../customers/presentation/customer_picker_sheet.dart';
import '../../products/application/products_providers.dart';
import '../../sales/application/sales_providers.dart';
import '../../sales/data/sale_models.dart';
import '../../sales/offline/checkout_service.dart';
import '../../sales/offline/pending_sale.dart';
import '../application/cart.dart';

const _methods = [
  PaymentMethod.cash,
  PaymentMethod.mobileMoney,
  PaymentMethod.card,
  PaymentMethod.credit,
  PaymentMethod.other,
];

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _amount = TextEditingController();
  String _method = PaymentMethod.cash;
  Customer? _customer;
  bool _submitting = false;

  /// One key per payment screen: if the request fails midway (e.g. network drop after the
  /// server already recorded the sale) the retry replays the same sale instead of duplicating it.
  final String _requestId = generateRequestId();

  @override
  void initState() {
    super.initState();
    _amount.text = formatQuantity(ref.read(cartProvider).total);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _received => parseUserNumber(_amount.text) ?? 0;

  void _selectMethod(String method, double total) {
    setState(() {
      final wasCredit = _method == PaymentMethod.credit;
      _method = method;
      if (method == PaymentMethod.credit) {
        _amount.text = '';
      } else if (wasCredit || _amount.text.trim().isEmpty) {
        _amount.text = formatQuantity(total);
      }
    });
  }

  /// Why the sale cannot be confirmed yet (null when it can).
  String? _blocker(Cart cart) {
    if (_method == PaymentMethod.mobileMoney) return null;
    final received = _received;
    final isCredit = _method == PaymentMethod.credit;

    if (!isCredit && received <= 0) {
      return 'Saisissez le montant reçu, ou choisissez « Crédit ».';
    }
    if (_method != PaymentMethod.cash && !isCredit && received > cart.total) {
      return 'Le montant dépasse le total à payer.';
    }
    if (received < cart.total && _customer == null) {
      return 'Sélectionnez un client pour vendre à crédit.';
    }
    return null;
  }

  Future<void> _pickCustomer() async {
    final customer = await showCustomerPicker(context);
    if (customer != null && mounted) setState(() => _customer = customer);
  }

  Future<void> _confirm(Cart cart) async {
    final applied = min(_received, cart.total);
    final change = _method == PaymentMethod.cash ? max(_received - cart.total, 0.0) : 0.0;

    final request = CheckoutRequest(
      items: [
        for (final line in cart.lines)
          CheckoutLine(productId: line.product.id, quantity: line.quantity),
      ],
      payments:
          applied > 0
              ? [
                CheckoutPayment(
                  // A deposit on a credit sale is cash; 'credit' itself is never a payment row.
                  method: _method == PaymentMethod.credit ? PaymentMethod.cash : _method,
                  amount: applied,
                ),
              ]
              : const [],
      discountTotal: cart.discount,
      customerId: _customer?.id,
      clientRequestId: _requestId,
    );

    // What the customer is handed if the server cannot be reached: the sale is then kept on the
    // phone (never lost) and this becomes its provisional receipt.
    final customer = _customer;
    final provisional = provisionalReceipt(
      requestId: _requestId,
      at: DateTime.now().toUtc(),
      subtotal: cart.subtotal,
      discountTotal: cart.discount,
      total: cart.total,
      amountPaid: applied,
      items: [
        for (final line in cart.lines)
          SaleItem(
            productName: line.product.name,
            unitPrice: line.product.salePrice,
            quantity: line.quantity,
            lineTotal: line.lineTotal,
          ),
      ],
      payments: [
        if (applied > 0)
          SalePayment(
            method: _method == PaymentMethod.credit ? PaymentMethod.cash : _method,
            amount: applied,
          ),
      ],
      customer:
          customer == null
              ? null
              : SaleCustomer(id: customer.id, fullName: customer.fullName, phone: customer.phone),
    );

    setState(() => _submitting = true);
    try {
      final outcome = await ref
          .read(checkoutServiceProvider)
          .checkout(request, provisional: provisional);
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(productsListProvider);
      ref.invalidate(salesHistoryProvider);
      if (!mounted) return;
      final queued = outcome.queued;
      final target = queued != null ? '/sales/pending/${queued.id}' : '/sales/${outcome.sale!.id}';
      context.go('$target?change=${change.toStringAsFixed(2)}');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final currency = ref.watch(currencyProvider);

    if (cart.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Mobile payment: the customer pays the owner's number or code, so there is no amount to type,
    // no change and no credit here — the payment is chosen, declared and verified on its own screens.
    final direct = _method == PaymentMethod.mobileMoney;
    final received = _received;
    final isCredit = _method == PaymentMethod.credit;
    final due = direct ? 0.0 : max(cart.total - received, 0.0);
    final change = _method == PaymentMethod.cash ? max(received - cart.total, 0.0) : 0.0;
    final blocker = _blocker(cart);

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('Total à payer', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(cart.total, currency: currency),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Moyen de paiement', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in _methods)
                  ChoiceChip(
                    label: Text(PaymentMethod.label(method)),
                    selected: _method == method,
                    onSelected: (_) => _selectMethod(method, cart.total),
                  ),
              ],
            ),
            if (direct)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Le client envoie l’argent sur votre numéro Orange Money, Mobile Money ou votre '
                  'code marchand. La vente est enregistrée quand vous avez vérifié le paiement.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            if (!direct)
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isCredit ? 'Acompte reçu en espèces (facultatif)' : 'Montant reçu',
                  suffixText: currency,
                ),
                onChanged: (_) => setState(() {}),
              ),
            if (!direct) const SizedBox(height: 12),
            if (change > 0)
              _InfoLine(
                icon: Icons.payments_outlined,
                color: AppColors.success,
                text: 'Monnaie à rendre : ${formatMoney(change, currency: currency)}',
              ),
            if (due > 0)
              _InfoLine(
                icon: Icons.schedule,
                color: AppColors.warning,
                text: 'Reste à crédit : ${formatMoney(due, currency: currency)}',
              ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(_customer?.fullName ?? 'Aucun client (vente au comptoir)'),
                subtitle: due > 0 ? const Text('Obligatoire pour une vente à crédit') : null,
                trailing:
                    _customer == null
                        ? TextButton(onPressed: _pickCustomer, child: const Text('Choisir'))
                        : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Retirer le client',
                          onPressed: () => setState(() => _customer = null),
                        ),
                onTap: _pickCustomer,
              ),
            ),
            if (blocker != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(blocker, style: const TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: direct ? 'Choisir le moyen de paiement' : 'Confirmer le paiement',
              loading: _submitting,
              onPressed:
                  blocker == null
                      ? () => direct ? context.push('/pos/pay', extra: _customer) : _confirm(cart)
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
