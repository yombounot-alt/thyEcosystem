import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../products/data/product_models.dart';

class CartLine {
  const CartLine({required this.product, required this.quantity});

  final Product product;
  final double quantity;

  double get lineTotal => round2(product.salePrice * quantity);
}

class Cart {
  const Cart({this.lines = const [], this.discount = 0});

  final List<CartLine> lines;
  final double discount;

  bool get isEmpty => lines.isEmpty;

  double get subtotal => round2(lines.fold(0.0, (sum, line) => sum + line.lineTotal));

  /// The server rejects a discount larger than the subtotal, so the UI blocks it up front.
  bool get discountTooHigh => discount > subtotal;

  double get total => discountTooHigh ? 0 : round2(subtotal - discount);

  /// Total number of units in the cart (a line of 3 counts as 3).
  double get unitCount => lines.fold(0.0, (sum, line) => sum + line.quantity);

  double quantityOf(String productId) {
    for (final line in lines) {
      if (line.product.id == productId) return line.quantity;
    }
    return 0;
  }

  Cart copyWith({List<CartLine>? lines, double? discount}) {
    return Cart(lines: lines ?? this.lines, discount: discount ?? this.discount);
  }
}

enum CartChange { applied, insufficientStock }

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);

class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  CartChange add(Product product) => setQuantity(product, state.quantityOf(product.id) + 1);

  /// Sets the quantity of [product]; a quantity of 0 or less removes the line.
  /// Refuses (and changes nothing) when it would exceed the stock on hand.
  CartChange setQuantity(Product product, double quantity) {
    if (quantity <= 0) {
      remove(product.id);
      return CartChange.applied;
    }
    if (quantity > product.currentStock) return CartChange.insufficientStock;

    final lines = [...state.lines];
    final index = lines.indexWhere((line) => line.product.id == product.id);
    final updated = CartLine(product: product, quantity: quantity);
    if (index >= 0) {
      lines[index] = updated;
    } else {
      lines.add(updated);
    }
    state = state.copyWith(lines: lines);
    return CartChange.applied;
  }

  void remove(String productId) {
    state = state.copyWith(
      lines: state.lines.where((line) => line.product.id != productId).toList(),
    );
  }

  void setDiscount(double discount) {
    state = state.copyWith(discount: discount < 0 ? 0 : discount);
  }

  void clear() => state = const Cart();
}
