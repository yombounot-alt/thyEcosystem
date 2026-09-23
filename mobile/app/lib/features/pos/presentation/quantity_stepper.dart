import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../products/data/product_models.dart';
import '../application/cart.dart';

/// Tells the cashier when a cart change was refused because of stock.
void showCartFeedback(BuildContext context, CartChange change, Product product) {
  if (change != CartChange.insufficientStock) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          'Stock insuffisant pour ${product.name} '
          '(disponible : ${formatQuantity(product.currentStock)})',
        ),
      ),
    );
}

/// − 3 + control. Tapping the number lets the cashier type an exact (possibly fractional) quantity.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
    this.onTapQuantity,
  });

  final double quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback? onTapQuantity;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Retirer un',
          visualDensity: VisualDensity.compact,
          onPressed: onDecrement,
        ),
        InkWell(
          onTap: onTapQuantity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              formatQuantity(quantity),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle, color: AppColors.primary),
          tooltip: 'Ajouter un',
          visualDensity: VisualDensity.compact,
          onPressed: onIncrement,
        ),
      ],
    );
  }
}
