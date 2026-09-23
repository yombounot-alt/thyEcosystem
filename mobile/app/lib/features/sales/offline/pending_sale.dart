import '../data/sale_models.dart';

/// [waiting]: will be sent as soon as the server answers. [failed]: the server refused it for
/// good (its [PendingSale.lastError] says why) — it stays on the phone until the user decides.
enum PendingSaleStatus { waiting, failed }

/// A sale that was rung up while the server could not be reached, kept on the phone until it can
/// be sent. The goods have already left the shop, so nothing here is ever dropped silently.
class PendingSale {
  const PendingSale({
    required this.id,
    required this.businessId,
    required this.createdAt,
    required this.request,
    required this.receipt,
    this.status = PendingSaleStatus.waiting,
    this.attempts = 0,
    this.lastError,
  });

  /// The request id of the sale: sending it twice can never sell twice.
  final String id;

  /// Only sent while this business is the active one.
  final String businessId;

  /// When the sale really happened (the server records this date, not the date it was received).
  final DateTime createdAt;
  final CheckoutRequest request;

  /// What the customer was given: shown, shared or exported as PDF while the sale waits.
  final Sale receipt;

  final PendingSaleStatus status;
  final int attempts;
  final String? lastError;

  bool get isFailed => status == PendingSaleStatus.failed;

  /// The request as it goes to the server: dated, and flagged as already happened.
  CheckoutRequest get requestToSend => request.asOffline(createdAt);

  PendingSale copyWith({
    PendingSaleStatus? status,
    int? attempts,
    String? lastError,
    bool clearError = false,
  }) {
    return PendingSale(
      id: id,
      businessId: businessId,
      createdAt: createdAt,
      request: request,
      receipt: receipt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  factory PendingSale.fromJson(Map<String, dynamic> json) {
    return PendingSale(
      id: json['id'] as String,
      businessId: json['businessId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      request: CheckoutRequest.fromJson(json['request'] as Map<String, dynamic>),
      receipt: Sale.fromJson(json['receipt'] as Map<String, dynamic>),
      status: json['status'] == 'failed' ? PendingSaleStatus.failed : PendingSaleStatus.waiting,
      attempts: json['attempts'] as int? ?? 0,
      lastError: json['lastError'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'businessId': businessId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'request': request.toJson(),
    'receipt': receipt.toJson(),
    'status': status.name,
    'attempts': attempts,
    'lastError': lastError,
  };
}

/// Number shown on the provisional receipt until the server gives the real one ("VTE-0012").
String provisionalSaleNumber(String requestId) {
  final letters = requestId.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
  return 'HL-${letters.substring(0, letters.length < 6 ? letters.length : 6)}';
}

/// The receipt of a sale that is not on the server yet.
Sale provisionalReceipt({
  required String requestId,
  required DateTime at,
  required double subtotal,
  required double discountTotal,
  required double total,
  required double amountPaid,
  required List<SaleItem> items,
  required List<SalePayment> payments,
  SaleCustomer? customer,
}) {
  return Sale(
    id: requestId,
    saleNumber: provisionalSaleNumber(requestId),
    subtotal: subtotal,
    discountTotal: discountTotal,
    total: total,
    amountPaid: amountPaid,
    amountDue: total > amountPaid ? total - amountPaid : 0,
    status: 'pending',
    soldAt: at,
    customer: customer,
    items: items,
    payments: payments,
    itemCount: items.length,
  );
}
