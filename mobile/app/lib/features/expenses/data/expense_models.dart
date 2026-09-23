import 'package:intl/intl.dart';

import '../../../core/api/json_helpers.dart';
import '../../customers/data/customer_models.dart';

/// Categories accepted by the backend, with their French labels.
class ExpenseCategory {
  ExpenseCategory._();

  static const codes = [
    'transport',
    'loyer',
    'salaire',
    'electricite',
    'internet',
    'achat',
    'maintenance',
    'autre',
  ];

  static String label(String code) {
    switch (code) {
      case 'transport':
        return 'Transport';
      case 'loyer':
        return 'Loyer';
      case 'salaire':
        return 'Salaire';
      case 'electricite':
        return 'Électricité';
      case 'internet':
        return 'Internet';
      case 'achat':
        return 'Achat';
      case 'maintenance':
        return 'Maintenance';
      case 'autre':
        return 'Autre';
      default:
        return code;
    }
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.description,
    required this.expenseDate,
  });

  final String id;
  final String category;
  final double amount;
  final String? description;
  final DateTime expenseDate;

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'] as String,
      category: json['category'] as String,
      amount: parseDecimal(json['amount']),
      description: json['description'] as String?,
      expenseDate: parseDateOnly(json['expenseDate'])!,
    );
  }
}

class ExpenseInput {
  const ExpenseInput({
    required this.category,
    required this.amount,
    required this.expenseDate,
    this.description,
  });

  final String category;
  final double amount;
  final DateTime expenseDate;
  final String? description;

  String get _day => DateFormat('yyyy-MM-dd').format(expenseDate);

  Map<String, dynamic> toCreateJson() => {
    'category': category,
    'amount': amount,
    'expenseDate': _day,
    if (description != null) 'description': description,
  };

  /// A cleared description is sent as null so it is actually cleared.
  Map<String, dynamic> toUpdateJson() => {
    'category': category,
    'amount': amount,
    'expenseDate': _day,
    'description': description,
  };
}

/// One page of expenses plus the total of the whole filtered period.
class ExpensePage {
  const ExpensePage({required this.items, required this.total, required this.totalAmount});

  final List<Expense> items;
  final int total;
  final double totalAmount;

  factory ExpensePage.fromJson(Map<String, dynamic> json) {
    return ExpensePage(
      items:
          (json['items'] as List<dynamic>)
              .map((e) => Expense.fromJson(e as Map<String, dynamic>))
              .toList(),
      total: json['total'] as int,
      totalAmount: parseDecimal(json['totalAmount'] ?? 0),
    );
  }
}
