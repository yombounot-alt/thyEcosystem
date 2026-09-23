import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/json_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/cart.dart';
import 'quantity_stepper.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  late final TextEditingController _discount;

  @override
  void initState() {
    super.initState();
    final discount = ref.read(cartProvider).discount;
    _discount = TextEditingController(text: discount > 0 ? formatQuantity(discount) : '');
  }

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  Future<void> _editQuantity(CartLine line) async {
    final controller = TextEditingController(text: formatQuantity(line.quantity));
    final entered = await showDialog<double>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(line.product.name),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantité'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, parseUserNumber(controller.text)),
                child: const Text('Valider'),
              ),
            ],
          ),
    );
    if (entered == null || !mounted) return;
    final change = ref.read(cartProvider.notifier).setQuantity(line.product, entered);
    showCartFeedback(context, change, line.product);
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Vider le panier ?'),
            content: const Text('Tous les articles seront retirés.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Vider'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(cartProvider.notifier).clear();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final currency = ref.watch(currencyProvider);
    final notifier = ref.read(cartProvider.notifier);

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Panier')),
        body: const EmptyState(
          icon: Icons.shopping_cart_outlined,
          message: 'Le panier est vide.\nRetournez à la caisse pour ajouter des produits.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panier'),
        actions: [TextButton(onPressed: _confirmClear, child: const Text('Vider'))],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: cart.lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final line = cart.lines[i];
                return Dismissible(
                  key: ValueKey(line.product.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => notifier.remove(line.product.id),
                  background: Container(
                    color: AppColors.danger,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.product.name),
                              Text(
                                formatMoney(line.product.salePrice, currency: currency),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        QuantityStepper(
                          quantity: line.quantity,
                          onDecrement: () => notifier.setQuantity(line.product, line.quantity - 1),
                          onIncrement:
                              () => showCartFeedback(
                                context,
                                notifier.setQuantity(line.product, line.quantity + 1),
                                line.product,
                              ),
                          onTapQuantity: () => _editQuantity(line),
                        ),
                        SizedBox(
                          width: 88,
                          child: Text(
                            formatMoney(line.lineTotal, currency: currency),
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SummaryRow('Sous-total', formatMoney(cart.subtotal, currency: currency)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(child: Text('Réduction')),
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: _discount,
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              isDense: true,
                              suffixText: currency,
                              errorText: cart.discountTooHigh ? 'Trop élevée' : null,
                            ),
                            onChanged: (value) => notifier.setDiscount(parseUserNumber(value) ?? 0),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _SummaryRow('TOTAL', formatMoney(cart.total, currency: currency), large: true),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      onPressed: cart.discountTooHigh ? null : () => context.push('/pos/payment'),
                      child: const Text(
                        'ENCAISSER',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.large = false});

  final String label;
  final String value;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style =
        large
            ? const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)
            : const TextStyle(fontSize: 15);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}
