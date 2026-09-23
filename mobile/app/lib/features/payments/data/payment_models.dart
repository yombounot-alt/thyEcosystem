import '../../../core/api/json_helpers.dart';
import '../../sales/data/sale_models.dart';
import 'payment_method_models.dart';

/// Where a payment stands. It is only "verified" once the OWNER has checked the money arrived:
/// the customer's declaration never validates anything by itself.
class PaymentStatus {
  PaymentStatus._();

  static const pending = 'pending';
  static const submitted = 'submitted';
  static const verified = 'verified';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';

  static const all = [pending, submitted, verified, rejected, cancelled];

  /// The short label shown on badges.
  static String label(String status) {
    switch (status) {
      case pending:
        return 'En attente';
      case submitted:
        return 'Vérification en cours';
      case verified:
        return 'Payé';
      case rejected:
        return 'Refusé';
      default:
        return 'Annulé';
    }
  }
}

/// Where the customer was told to pay — frozen when the payment started, so a later edit of the
/// owner's settings never changes what an existing payment says.
class PaymentOptionSnapshot {
  const PaymentOptionSnapshot({
    required this.provider,
    required this.displayName,
    required this.instructionSteps,
    required this.hasLogo,
    this.id,
    this.accountName,
    this.phoneNumber,
    this.merchantCode,
    this.ussdDial,
  });

  final String? id;
  final String provider;
  final String displayName;
  final String? accountName;
  final String? phoneNumber;
  final String? merchantCode;
  final List<String> instructionSteps;

  /// The code to dial for "Payer maintenant", already filled in; null when the owner set none.
  final String? ussdDial;
  final bool hasLogo;

  String? get destination => PaymentProvider.sendsToCode(provider) ? merchantCode : phoneNumber;

  factory PaymentOptionSnapshot.fromJson(Map<String, dynamic> json) {
    return PaymentOptionSnapshot(
      id: json['id'] as String?,
      provider: json['provider'] as String,
      displayName: json['displayName'] as String,
      accountName: json['accountName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      merchantCode: json['merchantCode'] as String?,
      instructionSteps: [
        for (final step in (json['instructionSteps'] as List<dynamic>? ?? const [])) step as String,
      ],
      ussdDial: json['ussdDial'] as String?,
      hasLogo: json['hasLogo'] as bool? ?? false,
    );
  }
}

/// What the payer declared. A claim to check, never proof.
class PaymentDeclaration {
  const PaymentDeclaration({
    required this.payerPhone,
    this.payerName,
    this.transactionReference,
    this.amountSent,
    this.paidAt,
    this.submittedAt,
  });

  final String? payerName;
  final String payerPhone;
  final String? transactionReference;
  final double? amountSent;
  final DateTime? paidAt;
  final DateTime? submittedAt;

  factory PaymentDeclaration.fromJson(Map<String, dynamic> json) {
    return PaymentDeclaration(
      payerName: json['payerName'] as String?,
      payerPhone: json['payerPhone'] as String,
      transactionReference: json['transactionReference'] as String?,
      amountSent: parseDecimalOrNull(json['amountSent']),
      paidAt: json['paidAt'] == null ? null : DateTime.parse(json['paidAt'] as String),
      submittedAt:
          json['submittedAt'] == null ? null : DateTime.parse(json['submittedAt'] as String),
    );
  }
}

DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String);

class ManualPayment {
  const ManualPayment({
    required this.id,
    required this.status,
    required this.amount,
    required this.currency,
    required this.createdAt,
    required this.method,
    required this.hasProof,
    required this.needsAttention,
    this.declaration,
    this.verifiedAt,
    this.rejectedAt,
    this.rejectionReason,
    this.cancelledAt,
    this.saleId,
    this.sale,
  });

  final String id;
  final String status;
  final double amount;
  final String currency;
  final DateTime createdAt;
  final PaymentOptionSnapshot method;
  final PaymentDeclaration? declaration;
  final bool hasProof;
  final DateTime? verifiedAt;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final DateTime? cancelledAt;

  /// The sale recorded when the owner verified the payment.
  final String? saleId;
  final Sale? sale;

  /// Verified, but the sale could not be recorded yet: verifying again finishes the job.
  final bool needsAttention;

  bool get isPending => status == PaymentStatus.pending;
  bool get isSubmitted => status == PaymentStatus.submitted;
  bool get isVerified => status == PaymentStatus.verified;
  bool get isRejected => status == PaymentStatus.rejected;
  bool get isCancelled => status == PaymentStatus.cancelled;

  /// The payer can (re)declare a payment that was not declared yet, or that was rejected.
  bool get canDeclare => isPending || isRejected;

  factory ManualPayment.fromJson(Map<String, dynamic> json) {
    final declaration = json['declaration'] as Map<String, dynamic>?;
    final sale = json['sale'] as Map<String, dynamic>?;
    return ManualPayment(
      id: json['id'] as String,
      status: json['status'] as String,
      amount: parseDecimal(json['amount']),
      currency: json['currency'] as String? ?? 'GNF',
      createdAt: DateTime.parse(json['createdAt'] as String),
      method: PaymentOptionSnapshot.fromJson(json['method'] as Map<String, dynamic>),
      declaration: declaration == null ? null : PaymentDeclaration.fromJson(declaration),
      hasProof: json['hasProof'] as bool? ?? false,
      verifiedAt: _date(json['verifiedAt']),
      rejectedAt: _date(json['rejectedAt']),
      rejectionReason: json['rejectionReason'] as String?,
      cancelledAt: _date(json['cancelledAt']),
      saleId: json['saleId'] as String?,
      sale: sale == null ? null : Sale.fromJson(sale),
      needsAttention: json['needsAttention'] as bool? ?? false,
    );
  }
}

/// How many payments are in each status (the "à vérifier" badge).
class PaymentSummary {
  const PaymentSummary({
    this.pending = 0,
    this.submitted = 0,
    this.verified = 0,
    this.rejected = 0,
    this.cancelled = 0,
  });

  static const zero = PaymentSummary();

  final int pending;
  final int submitted;
  final int verified;
  final int rejected;
  final int cancelled;

  factory PaymentSummary.fromJson(Map<String, dynamic> json) => PaymentSummary(
    pending: (json['pending'] as num?)?.toInt() ?? 0,
    submitted: (json['submitted'] as num?)?.toInt() ?? 0,
    verified: (json['verified'] as num?)?.toInt() ?? 0,
    rejected: (json['rejected'] as num?)?.toInt() ?? 0,
    cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
  );
}

/// What the payer fills in after sending the money.
class DeclarationInput {
  const DeclarationInput({
    required this.payerPhone,
    required this.transactionReference,
    required this.amountSent,
    this.payerName,
    this.paidAt,
  });

  final String payerPhone;
  final String transactionReference;
  final double amountSent;
  final String? payerName;
  final DateTime? paidAt;

  Map<String, dynamic> toJson() => {
    'payerPhone': payerPhone.trim(),
    'transactionReference': transactionReference.trim(),
    'amountSent': amountSent,
    if (payerName != null && payerName!.trim().isNotEmpty) 'payerName': payerName!.trim(),
    if (paidAt != null) 'paidAt': paidAt!.toUtc().toIso8601String(),
  };
}
