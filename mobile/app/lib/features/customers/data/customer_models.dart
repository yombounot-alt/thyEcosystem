import '../../../core/api/json_helpers.dart';

/// Calendar dates (credit due dates) come as "2026-09-21T00:00:00.000Z"; keep only the day so
/// it never shifts with the device time zone.
DateTime? parseDateOnly(Object? value) {
  if (value == null) return null;
  final parsed = DateTime.parse(value as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

class Customer {
  const Customer({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.currentBalance,
    this.address,
    this.notes,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String? address;
  final String? notes;

  /// Total the customer currently owes (open credits).
  final double currentBalance;

  bool get hasDebt => currentBalance > 0;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      currentBalance: parseDecimal(json['currentBalance'] ?? 0),
    );
  }
}

/// Fields the user edits. On update, cleared optional fields are sent as null so they really clear.
class CustomerInput {
  const CustomerInput({required this.fullName, this.phone, this.address, this.notes});

  final String fullName;
  final String? phone;
  final String? address;
  final String? notes;

  Map<String, dynamic> toCreateJson() => {
    'fullName': fullName,
    if (phone != null) 'phone': phone,
    if (address != null) 'address': address,
    if (notes != null) 'notes': notes,
  };

  Map<String, dynamic> toUpdateJson() => {
    'fullName': fullName,
    'phone': phone,
    'address': address,
    'notes': notes,
  };
}

class CreditStatus {
  CreditStatus._();

  static const open = 'open';
  static const partiallyPaid = 'partially_paid';
  static const paid = 'paid';
  static const voided = 'void';
}

/// Customer info attached to a credit in the business-wide overview.
class CreditCustomer {
  const CreditCustomer({required this.id, required this.fullName, this.phone});

  final String id;
  final String fullName;
  final String? phone;

  factory CreditCustomer.fromJson(Map<String, dynamic> json) {
    return CreditCustomer(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      phone: json['phone'] as String?,
    );
  }
}

class CustomerCredit {
  const CustomerCredit({
    required this.id,
    required this.customerId,
    required this.originalAmount,
    required this.remainingAmount,
    required this.status,
    required this.dueDate,
    required this.note,
    required this.createdAt,
    this.customer,
  });

  final String id;
  final String customerId;
  final double originalAmount;
  final double remainingAmount;
  final String status;
  final DateTime? dueDate;
  final String? note;
  final DateTime createdAt;
  final CreditCustomer? customer;

  factory CustomerCredit.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>?;
    return CustomerCredit(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      originalAmount: parseDecimal(json['originalAmount']),
      remainingAmount: parseDecimal(json['remainingAmount']),
      status: json['status'] as String,
      dueDate: parseDateOnly(json['dueDate']),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      customer: customer == null ? null : CreditCustomer.fromJson(customer),
    );
  }

  bool get isOutstanding => status == CreditStatus.open || status == CreditStatus.partiallyPaid;

  /// Late only once the due day is over — a credit due today is not late yet.
  bool isOverdue(DateTime now) {
    final due = dueDate;
    if (!isOutstanding || due == null) return false;
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }
}

/// One line of a customer's account: a debt added, or a payment received.
class StatementEntry {
  const StatementEntry({
    required this.isPayment,
    required this.date,
    required this.amount,
    this.method,
    this.note,
    this.creditStatus,
  });

  final bool isPayment;
  final DateTime date;
  final double amount;
  final String? method;
  final String? note;
  final String? creditStatus;

  factory StatementEntry.fromJson(Map<String, dynamic> json) {
    final isPayment = json['kind'] == 'payment';
    return StatementEntry(
      isPayment: isPayment,
      date: DateTime.parse(json['date'] as String),
      amount: parseDecimal(isPayment ? json['amount'] : json['originalAmount']),
      method: json['method'] as String?,
      note: json['note'] as String?,
      creditStatus: isPayment ? null : json['status'] as String?,
    );
  }
}
