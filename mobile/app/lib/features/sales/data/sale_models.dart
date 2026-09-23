import '../../../core/api/json_helpers.dart';

/// Payment methods the backend records. 'credit' is a UI-only choice (no payment row).
class PaymentMethod {
  PaymentMethod._();

  static const cash = 'cash';
  static const mobileMoney = 'mobile_money';
  static const card = 'card';
  static const other = 'other';
  static const credit = 'credit';

  static String label(String method) {
    switch (method) {
      case cash:
        return 'Espèces';
      case mobileMoney:
        return 'Paiement mobile';
      case card:
        return 'Carte';
      case credit:
        return 'Crédit';
      case other:
        return 'Autre';
      default:
        return method;
    }
  }
}

class SaleItem {
  const SaleItem({
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  final String productName;
  final double unitPrice;
  final double quantity;
  final double lineTotal;

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      productName: json['productNameSnapshot'] as String,
      unitPrice: parseDecimal(json['unitPrice']),
      quantity: parseDecimal(json['quantity']),
      lineTotal: parseDecimal(json['lineTotal']),
    );
  }

  Map<String, dynamic> toJson() => {
    'productNameSnapshot': productName,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'lineTotal': lineTotal,
  };
}

class SalePayment {
  const SalePayment({required this.method, required this.amount});

  final String method;
  final double amount;

  factory SalePayment.fromJson(Map<String, dynamic> json) {
    return SalePayment(method: json['method'] as String, amount: parseDecimal(json['amount']));
  }

  Map<String, dynamic> toJson() => {'method': method, 'amount': amount};
}

class SaleCustomer {
  const SaleCustomer({required this.id, required this.fullName, this.phone});

  final String id;
  final String fullName;
  final String? phone;

  factory SaleCustomer.fromJson(Map<String, dynamic> json) {
    return SaleCustomer(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'fullName': fullName, 'phone': phone};
}

class Sale {
  const Sale({
    required this.id,
    required this.saleNumber,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    required this.amountPaid,
    required this.amountDue,
    required this.status,
    required this.soldAt,
    required this.customer,
    required this.items,
    required this.payments,
    required this.itemCount,
  });

  final String id;
  final String saleNumber;
  final double subtotal;
  final double discountTotal;
  final double total;
  final double amountPaid;
  final double amountDue;
  final String status;
  final DateTime soldAt;
  final SaleCustomer? customer;
  final List<SaleItem> items;
  final List<SalePayment> payments;

  /// The list endpoint returns only a count; the detail endpoint returns the lines.
  final int itemCount;

  factory Sale.fromJson(Map<String, dynamic> json) {
    final items =
        (json['items'] as List<dynamic>? ?? const [])
            .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
            .toList();
    final count = json['_count'] as Map<String, dynamic>?;
    final customer = json['customer'] as Map<String, dynamic>?;

    return Sale(
      id: json['id'] as String,
      saleNumber: json['saleNumber'] as String,
      subtotal: parseDecimal(json['subtotal']),
      discountTotal: parseDecimal(json['discountTotal']),
      total: parseDecimal(json['total']),
      amountPaid: parseDecimal(json['amountPaid']),
      amountDue: parseDecimal(json['amountDue']),
      status: json['status'] as String,
      soldAt: DateTime.parse(json['soldAt'] as String),
      customer: customer == null ? null : SaleCustomer.fromJson(customer),
      items: items,
      payments:
          (json['payments'] as List<dynamic>? ?? const [])
              .map((e) => SalePayment.fromJson(e as Map<String, dynamic>))
              .toList(),
      itemCount: (count?['items'] as int?) ?? items.length,
    );
  }

  /// Same shape the API sends, so a sale kept on the phone reads back with [Sale.fromJson].
  Map<String, dynamic> toJson() => {
    'id': id,
    'saleNumber': saleNumber,
    'subtotal': subtotal,
    'discountTotal': discountTotal,
    'total': total,
    'amountPaid': amountPaid,
    'amountDue': amountDue,
    'status': status,
    'soldAt': soldAt.toUtc().toIso8601String(),
    'customer': customer?.toJson(),
    'items': items.map((i) => i.toJson()).toList(),
    'payments': payments.map((p) => p.toJson()).toList(),
  };

  bool get isVoid => status == 'void';
  bool get isOnCredit => amountDue > 0;
}

class CheckoutLine {
  const CheckoutLine({required this.productId, required this.quantity});

  final String productId;
  final double quantity;

  factory CheckoutLine.fromJson(Map<String, dynamic> json) => CheckoutLine(
    productId: json['productId'] as String,
    quantity: parseDecimal(json['quantity']),
  );

  Map<String, dynamic> toJson() => {'productId': productId, 'quantity': quantity};
}

class CheckoutPayment {
  const CheckoutPayment({required this.method, required this.amount});

  final String method;
  final double amount;

  factory CheckoutPayment.fromJson(Map<String, dynamic> json) =>
      CheckoutPayment(method: json['method'] as String, amount: parseDecimal(json['amount']));

  Map<String, dynamic> toJson() => {'method': method, 'amount': amount};
}

class CheckoutRequest {
  const CheckoutRequest({
    required this.items,
    required this.clientRequestId,
    this.payments = const [],
    this.discountTotal = 0,
    this.customerId,
    this.soldAt,
    this.offline = false,
  });

  final List<CheckoutLine> items;
  final List<CheckoutPayment> payments;
  final double discountTotal;
  final String? customerId;

  /// Stable across retries of the same sale so the server never sells twice.
  final String clientRequestId;

  /// When the sale really happened, for a sale rung up offline and sent later.
  final DateTime? soldAt;

  /// The sale already happened without the server: it must be recorded even if the server-side
  /// stock says otherwise (see the API's `offline` flag).
  final bool offline;

  /// The same sale, marked as rung up offline at [at].
  CheckoutRequest asOffline(DateTime at) => CheckoutRequest(
    items: items,
    clientRequestId: clientRequestId,
    payments: payments,
    discountTotal: discountTotal,
    customerId: customerId,
    soldAt: at,
    offline: true,
  );

  factory CheckoutRequest.fromJson(Map<String, dynamic> json) => CheckoutRequest(
    items:
        (json['items'] as List<dynamic>)
            .map((e) => CheckoutLine.fromJson(e as Map<String, dynamic>))
            .toList(),
    payments:
        (json['payments'] as List<dynamic>? ?? const [])
            .map((e) => CheckoutPayment.fromJson(e as Map<String, dynamic>))
            .toList(),
    discountTotal: parseDecimal(json['discountTotal'] ?? 0),
    customerId: json['customerId'] as String?,
    clientRequestId: json['clientRequestId'] as String,
    soldAt: json['soldAt'] == null ? null : DateTime.parse(json['soldAt'] as String),
    offline: json['offline'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'items': items.map((i) => i.toJson()).toList(),
    if (payments.isNotEmpty) 'payments': payments.map((p) => p.toJson()).toList(),
    if (discountTotal > 0) 'discountTotal': discountTotal,
    if (customerId != null) 'customerId': customerId,
    'clientRequestId': clientRequestId,
    if (soldAt != null) 'soldAt': soldAt!.toUtc().toIso8601String(),
    if (offline) 'offline': true,
  };
}
