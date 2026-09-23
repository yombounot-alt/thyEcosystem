import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../data/inventory_models.dart';

class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement, this.showProductName = false});

  final StockMovement movement;

  /// In the business-wide history the product is the title; on a product page the movement type is.
  final bool showProductName;

  @override
  Widget build(BuildContext context) {
    final incoming = movement.isIncoming;
    final color = incoming ? AppColors.success : AppColors.danger;
    final note = movement.note;
    final typeLabel = MovementType.label(movement.type);

    final subtitleParts = [
      if (showProductName) typeLabel,
      formatDateTime(movement.createdAt),
      if (note != null && note.isNotEmpty) note,
    ];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(incoming ? Icons.arrow_downward : Icons.arrow_upward, color: color),
      ),
      title: Text(showProductName ? (movement.productName ?? 'Produit') : typeLabel),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: Text(
        '${incoming ? '+' : '−'}${formatQuantity(movement.quantity)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}
