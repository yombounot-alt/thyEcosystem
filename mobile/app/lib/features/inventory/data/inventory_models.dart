import '../../../core/api/json_helpers.dart';

/// Movement types the backend understands; 'initial' and 'sale_out' are created by the server only.
class MovementType {
  MovementType._();

  static const initial = 'initial';
  static const purchaseIn = 'purchase_in';
  static const saleOut = 'sale_out';
  static const adjustmentIn = 'adjustment_in';
  static const adjustmentOut = 'adjustment_out';

  static bool isIncoming(String type) =>
      type == initial || type == purchaseIn || type == adjustmentIn;

  static String label(String type) {
    switch (type) {
      case initial:
        return 'Stock initial';
      case purchaseIn:
        return 'Entrée de stock';
      case saleOut:
        return 'Vente';
      case adjustmentIn:
        return 'Ajustement (+)';
      case adjustmentOut:
        return 'Sortie / ajustement (−)';
      default:
        return type;
    }
  }
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.unitCost,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String? productName;
  final String type;
  final double quantity;
  final double? unitCost;
  final String? note;
  final DateTime createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    return StockMovement(
      id: json['id'] as String,
      productId: json['productId'] as String,
      productName: product?['name'] as String?,
      type: json['type'] as String,
      quantity: parseDecimal(json['quantity']),
      unitCost: parseDecimalOrNull(json['unitCost']),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  bool get isIncoming => MovementType.isIncoming(type);
}
