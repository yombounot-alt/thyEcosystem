import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/app.dart';
import 'package:thy_app/core/api/api_exception.dart';
import 'package:thy_app/core/api/paginated.dart';
import 'package:thy_app/core/media/photo_picker.dart';
import 'package:thy_app/core/providers.dart';
import 'package:thy_app/core/scanning/barcode_scanner.dart';
import 'package:thy_app/core/storage/local_store.dart';
import 'package:thy_app/core/sharing/file_sharer.dart';
import 'package:thy_app/core/sharing/text_sharer.dart';
import 'package:thy_app/core/storage/token_storage.dart';
import 'package:thy_app/features/auth/application/auth_controller.dart';
import 'package:thy_app/features/auth/data/auth_api.dart';
import 'package:thy_app/features/auth/data/auth_models.dart';
import 'package:thy_app/features/categories/application/categories_providers.dart';
import 'package:thy_app/features/categories/data/categories_api.dart';
import 'package:thy_app/features/business/application/business_providers.dart';
import 'package:thy_app/features/business/data/business_api.dart';
import 'package:thy_app/features/categories/data/category_models.dart';
import 'package:thy_app/features/customers/application/customers_providers.dart';
import 'package:thy_app/features/customers/data/customer_models.dart';
import 'package:thy_app/features/customers/data/customers_api.dart';
import 'package:thy_app/features/dashboard/application/dashboard_providers.dart';
import 'package:thy_app/features/dashboard/data/dashboard_api.dart';
import 'package:thy_app/features/dashboard/data/dashboard_models.dart';
import 'package:thy_app/features/expenses/application/expenses_providers.dart';
import 'package:thy_app/features/expenses/data/expense_models.dart';
import 'package:thy_app/features/expenses/data/expenses_api.dart';
import 'package:thy_app/features/inventory/application/inventory_providers.dart';
import 'package:thy_app/features/inventory/data/inventory_api.dart';
import 'package:thy_app/features/inventory/data/inventory_models.dart';
import 'package:thy_app/features/payments/application/payments_providers.dart';
import 'package:thy_app/features/payments/data/payment_method_models.dart';
import 'package:thy_app/features/payments/data/payment_models.dart';
import 'package:thy_app/features/payments/data/payments_api.dart';
import 'package:thy_app/features/products/application/products_providers.dart';
import 'package:thy_app/features/products/data/product_models.dart';
import 'package:thy_app/features/products/data/products_api.dart';
import 'package:thy_app/features/sales/application/receipt_pdf.dart';
import 'package:thy_app/features/sales/application/sales_providers.dart';
import 'package:thy_app/features/sales/offline/sales_sync_service.dart';
import 'package:thy_app/features/sales/data/sale_models.dart';
import 'package:thy_app/features/sales/data/sales_api.dart';

class FakeTokenStorage extends TokenStorage {
  FakeTokenStorage({String? access, String? refresh}) : _access = access, _refresh = refresh;

  String? _access;
  String? _refresh;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> saveAccessToken(String accessToken) async {
    _access = accessToken;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}

class FakeAuthApi extends AuthApi {
  FakeAuthApi({this.role = 'owner', this.fullName = 'Tamba Camara'}) : super(Dio());

  /// Null until the person gives their name (first sign-in): `updateFullName` fills it.
  String? fullName;

  /// Phone numbers a sign-in code was requested for, and the codes tried.
  final List<String> requestedPhones = [];
  final List<String> triedCodes = [];

  /// The user's role in the business: an owner manages the payment settings and verifies payments,
  /// a cashier only rings up and declares.
  final String role;

  /// What the server would report for [role] (role grants; the app only hides what would be refused).
  List<String> get permissions =>
      role == 'owner'
          ? const [
            'catalog:view',
            'sales:create',
            'sales:view',
            'customers:manage',
            'payments:view',
            'payments:declare',
            'payments:verify',
            'payment_methods:manage',
            'reports:view',
            'finance:view_profit',
          ]
          : const [
            'catalog:view',
            'sales:create',
            'sales:view',
            'payments:view',
            'payments:declare',
          ];

  /// When set, reading the profile fails with it (no network, expired session, …).
  Object? meError;

  @override
  Future<void> requestOtp({required String phone}) async {
    requestedPhones.add(phone);
  }

  @override
  Future<TokenPair> verifyOtp({required String phone, required String code}) async {
    triedCodes.add(code);
    return const TokenPair(accessToken: 'access', refreshToken: 'refresh');
  }

  @override
  Future<void> updateFullName(String fullName) async {
    this.fullName = fullName;
  }

  @override
  Future<UserProfile> me() async {
    final failure = meError;
    if (failure != null) throw failure;
    return UserProfile(
      id: 'user-1',
      phone: '+224600000000',
      fullName: fullName,
      email: null,
      phoneVerified: true,
      activeBusinessId: 'biz-1',
      businesses: [
        BusinessSummary(
          id: 'biz-1',
          name: 'Boutique Demo',
          currency: 'GNF',
          role: role.toUpperCase(),
          permissions: permissions,
        ),
      ],
    );
  }
}

Product testProduct({
  required String id,
  required String name,
  double stock = 10,
  double? lowStockThreshold,
  double purchasePrice = 3000,
  double salePrice = 5000,
  bool isActive = true,
  String? sku,
  String? barcode,
  String? imageKey,
}) {
  return Product(
    imageKey: imageKey,
    id: id,
    name: name,
    categoryId: null,
    categoryName: null,
    sku: sku,
    barcode: barcode,
    unit: 'unite',
    purchasePrice: purchasePrice,
    salePrice: salePrice,
    currentStock: stock,
    lowStockThreshold: lowStockThreshold,
    isActive: isActive,
    description: null,
  );
}

class FakeProductsApi extends ProductsApi {
  FakeProductsApi(this.products) : super(Dio());

  final List<Product> products;
  final List<ProductInput> created = [];

  /// How many times the catalogue was read from the "server".
  int listCalls = 0;

  @override
  Future<Paginated<Product>> list({
    String? search,
    String? categoryId,
    bool? isActive,
    int page = 1,
    int pageSize = 100,
  }) async {
    listCalls++;
    final query = (search ?? '').toLowerCase();
    // Like the real API: the search also matches the SKU and the barcode ("contains").
    bool matches(Product p) =>
        p.name.toLowerCase().contains(query) ||
        (p.sku ?? '').toLowerCase().contains(query) ||
        (p.barcode ?? '').toLowerCase().contains(query);
    final items = products.where((p) => p.isActive == (isActive ?? true) && matches(p)).toList();
    return Paginated(items: items, total: items.length, page: page, pageSize: pageSize);
  }

  @override
  Future<List<Product>> lowStock() async => products.where((p) => p.isLowStock).toList();

  @override
  Future<Product> get(String id) async => products.firstWhere((p) => p.id == id);

  @override
  Future<Product> create(ProductInput input) async {
    created.add(input);
    final product = testProduct(
      id: 'new-${created.length}',
      name: input.name,
      stock: input.initialStock ?? 0,
      salePrice: input.salePrice,
    );
    products.add(product);
    return product;
  }

  final List<String> updatedIds = [];

  @override
  Future<Product> update(String id, ProductInput input) async {
    updatedIds.add(id);
    return products.firstWhere((p) => p.id == id);
  }

  // --- photos -------------------------------------------------------------------------------

  /// Bytes the "server" holds per product id.
  final Map<String, Uint8List> images = {};
  final List<({String productId, int size, String filename})> uploads = [];
  final List<String> imageDeletions = [];
  final List<String> imageFetches = [];

  /// When set, uploads fail with this message (the product itself is already saved by then).
  String? uploadError;

  void _setImageKey(String id, String? key) {
    final index = products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final p = products[index];
    products[index] = testProduct(
      id: p.id,
      name: p.name,
      stock: p.currentStock,
      salePrice: p.salePrice,
      imageKey: key,
    );
  }

  @override
  Future<Product> uploadImage(String id, Uint8List bytes, String filename) async {
    final error = uploadError;
    if (error != null) throw ApiException(error);
    uploads.add((productId: id, size: bytes.length, filename: filename));
    images[id] = bytes;
    _setImageKey(id, 'key-${uploads.length}');
    return products.firstWhere((p) => p.id == id);
  }

  @override
  Future<Product> deleteImage(String id) async {
    imageDeletions.add(id);
    images.remove(id);
    _setImageKey(id, null);
    return products.firstWhere((p) => p.id == id);
  }

  @override
  Future<Uint8List> fetchImage(String id) async {
    imageFetches.add(id);
    final bytes = images[id];
    if (bytes == null) throw ApiException('Ce produit n\'a pas de photo.', statusCode: 404);
    return bytes;
  }
}

/// Stands in for the camera scanner: "reads" [codes] one after the other, as if a barcode was
/// shown to the camera, and keeps what the app answered to each.
class FakeBarcodeScanner {
  FakeBarcodeScanner([this.codes = const []]);

  List<String> codes;
  final List<ScanFeedback> feedback = [];
  int opened = 0;
  bool? lastContinuous;
  String? lastTitle;

  Future<void> call(
    BuildContext context, {
    required ScanHandler onCode,
    bool continuous = false,
    String title = '',
  }) async {
    opened++;
    lastContinuous = continuous;
    lastTitle = title;
    for (final code in codes) {
      feedback.add(await onCode(code));
      if (!continuous) break; // a single scan closes after the first code
    }
  }
}

/// What the app handed to the system share sheet.
class SharedFile {
  const SharedFile({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    this.text,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final String? text;
}

/// A real 1×1 PNG, so `Image.memory` / `MemoryImage` have something valid to decode.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Stands in for the camera / gallery: returns [photo] (or null = the user cancelled).
class FakePhotoPicker {
  FakePhotoPicker([this.photo]);

  PickedPhoto? photo;
  final List<PhotoSource> requested = [];

  /// When set, opening the camera / gallery fails (e.g. permission denied).
  Object? error;

  Future<PickedPhoto?> call(PhotoSource source) async {
    requested.add(source);
    final failure = error;
    if (failure != null) throw failure;
    return photo;
  }
}

class RecordedMovement {
  const RecordedMovement({
    required this.productId,
    required this.type,
    required this.quantity,
    required this.unitCost,
    required this.note,
  });

  final String productId;
  final String type;
  final double quantity;
  final double? unitCost;
  final String? note;
}

class FakeInventoryApi extends InventoryApi {
  FakeInventoryApi() : super(Dio());

  final List<RecordedMovement> recorded = [];

  @override
  Future<Paginated<StockMovement>> list({
    String? productId,
    int page = 1,
    int pageSize = 50,
  }) async {
    return Paginated(items: const [], total: 0, page: page, pageSize: pageSize);
  }

  @override
  Future<void> record({
    required String productId,
    required String type,
    required double quantity,
    double? unitCost,
    String? note,
  }) async {
    recorded.add(
      RecordedMovement(
        productId: productId,
        type: type,
        quantity: quantity,
        unitCost: unitCost,
        note: note,
      ),
    );
  }
}

class FakeCategoriesApi extends CategoriesApi {
  FakeCategoriesApi() : super(Dio());

  @override
  Future<List<Category>> list() async => const [Category(id: 'cat-1', name: 'Boissons')];
}

CustomerCredit testCredit({
  required String id,
  required String customerId,
  required double remaining,
  double? original,
  DateTime? dueDate,
  String status = CreditStatus.open,
  String? note,
}) {
  return CustomerCredit(
    id: id,
    customerId: customerId,
    originalAmount: original ?? remaining,
    remainingAmount: remaining,
    status: status,
    dueDate: dueDate,
    note: note,
    createdAt: DateTime.utc(2026, 9, 1),
  );
}

class RecordedPayment {
  const RecordedPayment(this.customerId, this.amount, this.method, this.note);

  final String customerId;
  final double amount;
  final String method;
  final String? note;
}

class RecordedDebt {
  const RecordedDebt(this.customerId, this.amount, this.dueDate, this.note);

  final String customerId;
  final double amount;
  final DateTime? dueDate;
  final String? note;
}

/// Keeps customers, their debts and the account statement in memory and applies payments/debts
/// to the balance, so screens that refetch after a change show the new state.
class FakeCustomersApi extends CustomersApi {
  FakeCustomersApi([List<Customer>? customers, Map<String, List<CustomerCredit>>? credits])
    : customers = customers ?? [],
      creditsByCustomer = credits ?? {},
      super(Dio());

  final List<Customer> customers;
  final Map<String, List<CustomerCredit>> creditsByCustomer;
  final List<RecordedPayment> payments = [];
  final List<RecordedDebt> debts = [];
  final List<CustomerInput> updates = [];
  final List<String> deleted = [];
  final List<CustomerInput> created = [];

  int _indexOf(String id) => customers.indexWhere((c) => c.id == id);

  void _setBalance(String id, double balance) {
    final index = _indexOf(id);
    final c = customers[index];
    customers[index] = Customer(
      id: c.id,
      fullName: c.fullName,
      phone: c.phone,
      address: c.address,
      notes: c.notes,
      currentBalance: balance,
    );
  }

  /// How many times the customers were read from the "server".
  int listCalls = 0;

  @override
  Future<Paginated<Customer>> list({String? search, int page = 1, int pageSize = 100}) async {
    listCalls++;
    final query = (search ?? '').toLowerCase();
    final items = customers.where((c) => c.fullName.toLowerCase().contains(query)).toList();
    return Paginated(items: items, total: items.length, page: page, pageSize: pageSize);
  }

  @override
  Future<Customer> get(String id) async => customers[_indexOf(id)];

  @override
  Future<Customer> create({
    required String fullName,
    String? phone,
    String? address,
    String? notes,
  }) async {
    created.add(CustomerInput(fullName: fullName, phone: phone, address: address, notes: notes));
    final customer = Customer(
      id: 'cust-${customers.length + 1}',
      fullName: fullName,
      phone: phone,
      address: address,
      notes: notes,
      currentBalance: 0,
    );
    customers.add(customer);
    return customer;
  }

  @override
  Future<Customer> update(String id, CustomerInput input) async {
    updates.add(input);
    final c = customers[_indexOf(id)];
    customers[_indexOf(id)] = Customer(
      id: id,
      fullName: input.fullName,
      phone: input.phone,
      address: input.address,
      notes: input.notes,
      currentBalance: c.currentBalance,
    );
    return customers[_indexOf(id)];
  }

  @override
  Future<void> delete(String id) async {
    if (customers[_indexOf(id)].hasDebt) {
      throw ApiException(
        'Ce client a des ventes ou des crédits associés, il ne peut pas être supprimé.',
      );
    }
    deleted.add(id);
    customers.removeAt(_indexOf(id));
  }

  @override
  Future<List<CustomerCredit>> credits(String customerId) async {
    return creditsByCustomer[customerId] ?? const [];
  }

  @override
  Future<List<StatementEntry>> statement(String customerId) async {
    return [
      for (final credit in creditsByCustomer[customerId] ?? <CustomerCredit>[])
        StatementEntry(
          isPayment: false,
          date: credit.createdAt,
          amount: credit.originalAmount,
          note: credit.note,
          creditStatus: credit.status,
        ),
      for (final payment in payments.where((p) => p.customerId == customerId))
        StatementEntry(
          isPayment: true,
          date: DateTime.utc(2026, 9, 19),
          amount: payment.amount,
          method: payment.method,
          note: payment.note,
        ),
    ];
  }

  @override
  Future<void> grantCredit(
    String customerId, {
    required double amount,
    DateTime? dueDate,
    String? note,
  }) async {
    debts.add(RecordedDebt(customerId, amount, dueDate, note));
    _setBalance(customerId, customers[_indexOf(customerId)].currentBalance + amount);
    creditsByCustomer
        .putIfAbsent(customerId, () => [])
        .add(
          testCredit(
            id: 'credit-new-${debts.length}',
            customerId: customerId,
            remaining: amount,
            dueDate: dueDate,
            note: note,
          ),
        );
  }

  @override
  Future<void> recordPayment(
    String customerId, {
    required double amount,
    required String method,
    String? note,
  }) async {
    payments.add(RecordedPayment(customerId, amount, method, note));
    _setBalance(customerId, customers[_indexOf(customerId)].currentBalance - amount);
  }

  @override
  Future<Paginated<CustomerCredit>> outstandingCredits({int page = 1, int pageSize = 100}) async {
    final items = [
      for (final entry in creditsByCustomer.entries)
        for (final credit in entry.value.where((c) => c.isOutstanding))
          CustomerCredit(
            id: credit.id,
            customerId: credit.customerId,
            originalAmount: credit.originalAmount,
            remainingAmount: credit.remainingAmount,
            status: credit.status,
            dueDate: credit.dueDate,
            note: credit.note,
            createdAt: credit.createdAt,
            customer: CreditCustomer(
              id: entry.key,
              fullName: customers.firstWhere((c) => c.id == entry.key).fullName,
            ),
          ),
    ];
    return Paginated(items: items, total: items.length, page: page, pageSize: pageSize);
  }
}

class FakeExpensesApi extends ExpensesApi {
  FakeExpensesApi([List<Expense>? expenses]) : expenses = expenses ?? [], super(Dio());

  final List<Expense> expenses;
  final List<ExpenseInput> created = [];
  final List<ExpenseInput> updated = [];
  final List<String> deleted = [];

  @override
  Future<ExpensePage> list({DateTime? from, DateTime? to, int page = 1, int pageSize = 100}) async {
    final items =
        expenses.where((e) {
          if (from != null && e.expenseDate.isBefore(from)) return false;
          if (to != null && e.expenseDate.isAfter(to)) return false;
          return true;
        }).toList();
    return ExpensePage(
      items: items,
      total: items.length,
      totalAmount: items.fold(0.0, (sum, e) => sum + e.amount),
    );
  }

  @override
  Future<Expense> get(String id) async => expenses.firstWhere((e) => e.id == id);

  @override
  Future<Expense> create(ExpenseInput input) async {
    created.add(input);
    final expense = Expense(
      id: 'exp-new-${created.length}',
      category: input.category,
      amount: input.amount,
      description: input.description,
      expenseDate: input.expenseDate,
    );
    expenses.add(expense);
    return expense;
  }

  @override
  Future<Expense> update(String id, ExpenseInput input) async {
    updated.add(input);
    final index = expenses.indexWhere((e) => e.id == id);
    expenses[index] = Expense(
      id: id,
      category: input.category,
      amount: input.amount,
      description: input.description,
      expenseDate: input.expenseDate,
    );
    return expenses[index];
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    expenses.removeWhere((e) => e.id == id);
  }
}

class FakeDashboardApi extends DashboardApi {
  FakeDashboardApi({DashboardSummary? summary})
    : summaryToReturn = summary ?? emptySummary,
      super(Dio());

  static const emptySummary = DashboardSummary(
    revenue: 0,
    cogs: 0,
    expensesTotal: 0,
    profit: 0,
    ordersCount: 0,
    lowStockCount: 0,
    outstandingCredits: 0,
    overdueCreditsCount: 0,
  );

  final DashboardSummary summaryToReturn;
  final List<DashboardPeriod> requestedPeriods = [];

  @override
  Future<DashboardSummary> summary(DashboardPeriod period) async {
    requestedPeriods.add(period);
    return summaryToReturn;
  }

  @override
  Future<List<SalesChartPoint>> salesChart({int days = 7}) async {
    return [
      for (var i = 0; i < days; i++)
        SalesChartPoint(date: DateTime(2026, 9, 13 + i), revenue: i == days - 1 ? 31000 : 0),
    ];
  }

  @override
  Future<List<TopProduct>> topProducts(DashboardPeriod period, {int limit = 5}) async {
    return const [
      TopProduct(productId: 'p2', name: 'Sucre en poudre 1kg', quantity: 2, revenue: 17000),
      TopProduct(productId: 'p1', name: 'Eau minérale 1.5L', quantity: 3, revenue: 15000),
    ];
  }
}

class FakeBusinessApi extends BusinessApi {
  FakeBusinessApi() : super(Dio());

  @override
  Future<BusinessDetails> details(String businessId) async {
    return const BusinessDetails(
      id: 'biz-1',
      name: 'Boutique Demo',
      currency: 'GNF',
      phone: '+224600000000',
      address: 'Kaloum, Conakry',
    );
  }
}

/// Behaves like the real server for what the UI relies on: totals from the catalog prices,
/// idempotency on clientRequestId, credit for the unpaid remainder, void.
class FakeSalesApi extends SalesApi {
  FakeSalesApi({required this.catalog, this.customers = const []}) : super(Dio());

  final List<Product> catalog;
  final List<Customer> customers;

  final List<CheckoutRequest> requests = [];
  final List<String> voided = [];
  final Map<String, Sale> _byId = {};
  final Map<String, Sale> _byRequestId = {};

  /// Number of upcoming checkouts that fail with a server-style error (the server answered).
  int failNextCheckouts = 0;

  /// While true the server cannot be reached at all.
  bool networkDown = false;

  /// The server refuses every checkout for good (a 400) with this message…
  String? rejectWith;

  /// …except the sales with these request ids, which are refused while this is set.
  Set<String>? rejectOnlyRequests;

  /// When set, the server answers every checkout with this HTTP status (e.g. 503).
  int? failWithStatus;

  /// The next checkout is recorded by the server but its answer never arrives.
  bool loseNextResponse = false;

  @override
  Future<Sale> checkout(CheckoutRequest request) async {
    requests.add(request);
    if (networkDown) {
      throw ApiException(
        'Impossible de contacter le serveur. Vérifiez votre connexion.',
        isConnectionProblem: true,
      );
    }
    final status = failWithStatus;
    if (status != null) throw ApiException('Erreur du serveur', statusCode: status);
    final refused = rejectWith;
    if (refused != null &&
        (rejectOnlyRequests == null || rejectOnlyRequests!.contains(request.clientRequestId))) {
      throw ApiException(refused, statusCode: 400);
    }
    if (failNextCheckouts > 0) {
      failNextCheckouts--;
      throw ApiException('Connexion perdue. Veuillez réessayer.');
    }
    final replay = _byRequestId[request.clientRequestId];
    if (replay != null) return replay;

    final items = [
      for (final line in request.items)
        () {
          final product = catalog.firstWhere((p) => p.id == line.productId);
          return SaleItem(
            productName: product.name,
            unitPrice: product.salePrice,
            quantity: line.quantity,
            lineTotal: product.salePrice * line.quantity,
          );
        }(),
    ];
    final subtotal = items.fold(0.0, (sum, i) => sum + i.lineTotal);
    final total = subtotal - request.discountTotal;
    final paid = request.payments.fold(0.0, (sum, p) => sum + p.amount);
    final customer = customers.where((c) => c.id == request.customerId).firstOrNull;

    final sale = Sale(
      id: 'sale-${_byId.length + 1}',
      saleNumber: 'VTE-${(_byId.length + 1).toString().padLeft(4, '0')}',
      subtotal: subtotal,
      discountTotal: request.discountTotal,
      total: total,
      amountPaid: paid,
      amountDue: total > paid ? total - paid : 0,
      status: 'completed',
      soldAt: request.soldAt ?? DateTime.utc(2026, 9, 19, 10, 30),
      customer:
          customer == null ? null : SaleCustomer(id: customer.id, fullName: customer.fullName),
      items: items,
      payments: [for (final p in request.payments) SalePayment(method: p.method, amount: p.amount)],
      itemCount: items.length,
    );
    _byId[sale.id] = sale;
    _byRequestId[request.clientRequestId] = sale;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw ApiException(
        'Impossible de contacter le serveur. Vérifiez votre connexion.',
        isConnectionProblem: true,
      );
    }
    return sale;
  }

  /// How many sales the server really holds.
  int get recordedCount => _byId.length;

  @override
  Future<Sale> get(String id) async => _byId[id]!;

  @override
  Future<Paginated<Sale>> list({int page = 1, int pageSize = 50}) async {
    final items = _byId.values.toList().reversed.toList();
    return Paginated(items: items, total: items.length, page: page, pageSize: pageSize);
  }

  @override
  Future<Sale> voidSale(String id) async {
    voided.add(id);
    final original = _byId[id]!;
    final voidedSale = Sale(
      id: original.id,
      saleNumber: original.saleNumber,
      subtotal: original.subtotal,
      discountTotal: original.discountTotal,
      total: original.total,
      amountPaid: original.amountPaid,
      amountDue: original.amountDue,
      status: 'void',
      soldAt: original.soldAt,
      customer: original.customer,
      items: original.items,
      payments: original.payments,
      itemCount: original.itemCount,
    );
    _byId[id] = voidedSale;
    return voidedSale;
  }
}

/// The owner's payment settings, as the server keeps them: several accounts per operator, active or
/// not, with the default steps when the owner wrote none.
class FakePaymentMethodsApi extends PaymentMethodsApi {
  FakePaymentMethodsApi({List<PaymentOption> initial = const []}) : super(Dio()) {
    for (final option in initial) {
      _options[option.id] = option;
    }
  }

  final Map<String, PaymentOption> _options = {};
  final List<PaymentOptionInput> created = [];
  final Map<String, PaymentOptionInput> updated = {};
  final List<String> deleted = [];
  final Map<String, List<int>> logos = {};

  /// Ids that were used by a payment: the server refuses to delete them.
  final Set<String> used = {};

  /// A cashier only receives the active options.
  bool activeOnly = false;
  bool networkDown = false;
  int _count = 0;

  List<PaymentOption> get all => _options.values.toList();

  ApiException get _down => ApiException(
    'Impossible de contacter le serveur. Vérifiez votre connexion.',
    isConnectionProblem: true,
  );

  static List<String> defaultSteps(String provider) => [
    'Ouvrez ${PaymentProvider.label(provider)}.',
    'Effectuez un transfert vers le numéro indiqué.',
    'Envoyez exactement le montant affiché.',
    'Conservez la référence de transaction.',
    'Revenez dans l’application.',
    'Cliquez sur « J’ai effectué le paiement ».',
    'Saisissez votre référence de transaction.',
    'Votre paiement sera vérifié avant validation.',
  ];

  PaymentOption _build(String id, PaymentOptionInput input, {bool hasLogo = false}) {
    String? blank(String value) => value.trim().isEmpty ? null : value.trim();
    final custom = blank(input.instructions);
    return PaymentOption(
      id: id,
      provider: input.provider,
      displayName: blank(input.displayName) ?? PaymentProvider.label(input.provider),
      accountName: blank(input.accountName),
      phoneNumber: blank(input.phoneNumber),
      merchantCode: blank(input.merchantCode),
      instructions: custom,
      instructionSteps:
          custom == null
              ? defaultSteps(input.provider)
              : custom.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(),
      ussdCode: blank(input.ussdCode),
      hasLogo: hasLogo,
      isActive: input.isActive,
      updatedAt: DateTime.utc(2026, 9, 21, 10),
    );
  }

  @override
  Future<List<PaymentOption>> list() async {
    if (networkDown) throw _down;
    final all = _options.values.toList();
    return activeOnly ? all.where((o) => o.isActive).toList() : all;
  }

  @override
  Future<PaymentOption> create(PaymentOptionInput input) async {
    if (networkDown) throw _down;
    created.add(input);
    final option = _build('opt-${++_count}0000000', input);
    _options[option.id] = option;
    return option;
  }

  @override
  Future<PaymentOption> update(String id, PaymentOptionInput input) async {
    if (networkDown) throw _down;
    updated[id] = input;
    return _options[id] = _build(id, input, hasLogo: _options[id]!.hasLogo);
  }

  @override
  Future<PaymentOption> setActive(String id, bool active) async {
    if (networkDown) throw _down;
    final o = _options[id]!;
    return _options[id] = PaymentOption(
      id: o.id,
      provider: o.provider,
      displayName: o.displayName,
      accountName: o.accountName,
      phoneNumber: o.phoneNumber,
      merchantCode: o.merchantCode,
      instructions: o.instructions,
      instructionSteps: o.instructionSteps,
      ussdCode: o.ussdCode,
      hasLogo: o.hasLogo,
      isActive: active,
      updatedAt: o.updatedAt,
    );
  }

  @override
  Future<void> delete(String id) async {
    if (networkDown) throw _down;
    if (used.contains(id)) {
      throw ApiException(
        'Ce moyen de paiement a déjà été utilisé : désactivez-le plutôt que de le supprimer.',
        statusCode: 409,
      );
    }
    deleted.add(id);
    _options.remove(id);
  }

  @override
  Future<PaymentOption> uploadLogo(String id, Uint8List bytes, String filename) async {
    logos[id] = bytes;
    final o = _options[id]!;
    return _options[id] = PaymentOption(
      id: o.id,
      provider: o.provider,
      displayName: o.displayName,
      accountName: o.accountName,
      phoneNumber: o.phoneNumber,
      merchantCode: o.merchantCode,
      instructions: o.instructions,
      instructionSteps: o.instructionSteps,
      ussdCode: o.ussdCode,
      hasLogo: true,
      isActive: o.isActive,
      updatedAt: o.updatedAt,
    );
  }

  @override
  Future<Uint8List> fetchLogo(String id) async {
    final bytes = logos[id];
    if (bytes == null) throw ApiException('Aucun logo', statusCode: 404);
    return Uint8List.fromList(bytes);
  }
}

class _PaymentRow {
  _PaymentRow({
    required this.id,
    required this.option,
    required this.amount,
    required this.request,
  });

  final String id;
  final PaymentOption option;
  final double amount;
  final String request;
  String status = PaymentStatus.pending;
  PaymentDeclaration? declaration;
  String? rejectionReason;
  String? saleId;
  Sale? sale;
  bool hasProof = false;
  Uint8List? proof;
  final createdAt = DateTime.utc(2026, 9, 21, 9);
  late CheckoutRequest checkout;
}

/// The direct-payment server: it prices the basket itself, keeps a transaction reference to one
/// payment, needs the exact amount, and records the sale only when the owner verifies.
class FakePaymentsApi extends PaymentsApi {
  FakePaymentsApi({required this.sales, required this.catalog, required this.options})
    : super(Dio());

  final FakeSalesApi sales;
  final List<Product> catalog;
  final FakePaymentMethodsApi options;

  final Map<String, _PaymentRow> _rows = {};
  final Map<String, String> _idByRequest = {};
  final List<String> submitCalls = [];
  final List<String> verified = [];
  final List<({String id, String? reason})> rejected = [];
  final List<String> cancelled = [];
  bool networkDown = false;
  int _count = 0;

  ApiException get _down => ApiException(
    'Impossible de contacter le serveur. Vérifiez votre connexion.',
    isConnectionProblem: true,
  );

  List<ManualPayment> get all => _rows.values.map(_view).toList();
  ManualPayment get last => _view(_rows.values.last);
  String get lastId => _rows.keys.last;

  ManualPayment _view(_PaymentRow r) {
    final o = r.option;
    return ManualPayment(
      id: r.id,
      status: r.status,
      amount: r.amount,
      currency: 'GNF',
      createdAt: r.createdAt,
      method: PaymentOptionSnapshot(
        id: o.id,
        provider: o.provider,
        displayName: o.displayName,
        accountName: o.accountName,
        phoneNumber: o.phoneNumber,
        merchantCode: o.merchantCode,
        instructionSteps: o.instructionSteps,
        ussdDial: o.ussdCode
            ?.replaceAll('{numero}', (o.phoneNumber ?? '').replaceAll(RegExp(r'\D'), ''))
            .replaceAll('{montant}', r.amount.round().toString()),
        hasLogo: o.hasLogo,
      ),
      declaration: r.declaration,
      hasProof: r.hasProof,
      rejectionReason: r.rejectionReason,
      saleId: r.saleId,
      sale: r.sale,
      needsAttention: false,
    );
  }

  _PaymentRow _row(String id) {
    if (networkDown) throw _down;
    return _rows[id] ?? (throw ApiException('Paiement introuvable.', statusCode: 404));
  }

  static String _key(String reference) =>
      reference.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  @override
  Future<ManualPayment> start({
    required List<CheckoutLine> items,
    required String paymentMethodId,
    required String clientRequestId,
    double discountTotal = 0,
    String? customerId,
  }) async {
    if (networkDown) throw _down;
    final replay = _idByRequest[clientRequestId];
    if (replay != null) return _view(_rows[replay]!);

    final option = options.all.where((o) => o.id == paymentMethodId).firstOrNull;
    if (option == null) throw ApiException('Moyen de paiement introuvable.', statusCode: 404);
    if (!option.isActive) {
      throw ApiException('Ce moyen de paiement n’est pas proposé pour le moment.', statusCode: 400);
    }

    final subtotal = items.fold(0.0, (sum, line) {
      final product = catalog.firstWhere((p) => p.id == line.productId);
      return sum + product.salePrice * line.quantity;
    });
    final row = _PaymentRow(
      id: 'pay-${++_count}',
      option: option,
      amount: subtotal - discountTotal,
      request: clientRequestId,
    );
    row.checkout = CheckoutRequest(
      items: items,
      discountTotal: discountTotal,
      customerId: customerId,
      clientRequestId: clientRequestId,
      payments: [CheckoutPayment(method: PaymentMethod.mobileMoney, amount: row.amount)],
    );
    _rows[row.id] = row;
    _idByRequest[clientRequestId] = row.id;
    options.used.add(option.id);
    return _view(row);
  }

  @override
  Future<ManualPayment> get(String id) async => _view(_row(id));

  @override
  Future<Paginated<ManualPayment>> list({String? status, int page = 1, int pageSize = 50}) async {
    if (networkDown) throw _down;
    final rows = _rows.values.where((r) => status == null || r.status == status).toList().reversed;
    final items = rows.map(_view).toList();
    return Paginated(items: items, total: items.length, page: page, pageSize: pageSize);
  }

  @override
  Future<PaymentSummary> summary() async {
    if (networkDown) throw _down;
    int count(String s) => _rows.values.where((r) => r.status == s).length;
    return PaymentSummary(
      pending: count(PaymentStatus.pending),
      submitted: count(PaymentStatus.submitted),
      verified: count(PaymentStatus.verified),
      rejected: count(PaymentStatus.rejected),
      cancelled: count(PaymentStatus.cancelled),
    );
  }

  @override
  Future<ManualPayment> submit(String id, DeclarationInput input) async {
    final row = _row(id);
    submitCalls.add(id);

    if (input.amountSent != row.amount) {
      throw ApiException(
        'Le montant envoyé doit être exactement le montant à payer.',
        statusCode: 400,
      );
    }
    final reference = input.transactionReference.trim();
    if (reference.length < 4) {
      throw ApiException('Référence de transaction invalide.', statusCode: 400);
    }
    final key = _key(reference);
    final clash = _rows.values.any(
      (r) =>
          r.id != id &&
          r.option.provider == row.option.provider &&
          (r.status == PaymentStatus.submitted || r.status == PaymentStatus.verified) &&
          r.declaration != null &&
          _key(r.declaration!.transactionReference ?? '') == key,
    );
    if (clash) {
      throw ApiException(
        'Cette référence de transaction a déjà été utilisée pour un autre paiement.',
        statusCode: 409,
      );
    }
    if (row.status != PaymentStatus.pending && row.status != PaymentStatus.rejected) {
      throw ApiException('Ce paiement ne peut plus être déclaré.', statusCode: 409);
    }
    row
      ..status = PaymentStatus.submitted
      ..rejectionReason = null
      ..declaration = PaymentDeclaration(
        payerName: input.payerName,
        payerPhone: input.payerPhone,
        transactionReference: reference,
        amountSent: input.amountSent,
        paidAt: input.paidAt,
        submittedAt: DateTime.utc(2026, 9, 21, 9, 5),
      );
    return _view(row);
  }

  @override
  Future<ManualPayment> verify(String id) async {
    final row = _row(id);
    if (row.status == PaymentStatus.verified) return _view(row);
    if (row.status != PaymentStatus.submitted) {
      throw ApiException('Ce paiement ne peut pas être validé.', statusCode: 409);
    }
    verified.add(id);
    final sale = await sales.checkout(row.checkout);
    row
      ..status = PaymentStatus.verified
      ..saleId = sale.id
      ..sale = sale;
    return _view(row);
  }

  @override
  Future<ManualPayment> reject(String id, {String? reason}) async {
    final row = _row(id);
    rejected.add((id: id, reason: reason));
    if (row.status != PaymentStatus.submitted) {
      throw ApiException('Ce paiement ne peut pas être refusé.', statusCode: 409);
    }
    row
      ..status = PaymentStatus.rejected
      ..rejectionReason = (reason == null || reason.trim().isEmpty) ? null : reason.trim();
    return _view(row);
  }

  @override
  Future<ManualPayment> cancel(String id) async {
    final row = _row(id);
    cancelled.add(id);
    if (row.status == PaymentStatus.pending || row.status == PaymentStatus.submitted) {
      row.status = PaymentStatus.cancelled;
    }
    return _view(row);
  }

  @override
  Future<ManualPayment> uploadProof(String id, Uint8List bytes, String filename) async {
    final row = _row(id);
    row
      ..hasProof = true
      ..proof = bytes;
    return _view(row);
  }

  @override
  Future<Uint8List> fetchProof(String id) async {
    final row = _row(id);
    return row.proof ?? (throw ApiException('Aucune preuve', statusCode: 404));
  }
}

/// Boots the whole app with an already-authenticated session and the given fake APIs.
/// Anything passed to [sharedTexts] receives the text of receipts the user shares.
Future<void> pumpAuthenticatedApp(
  WidgetTester tester, {
  FakeProductsApi? products,
  FakeInventoryApi? inventory,
  FakeSalesApi? sales,
  FakePaymentMethodsApi? paymentMethods,
  FakePaymentsApi? payments,
  List<String>? copiedTexts,
  List<String>? dialedCodes,
  FakeCustomersApi? customers,
  FakeExpensesApi? expenses,
  FakeDashboardApi? dashboard,
  FakePhotoPicker? photoPicker,
  List<String>? sharedTexts,
  List<SharedFile>? sharedFiles,
  Object? fileShareError,
  ReceiptFonts? receiptFonts,
  FakeAuthApi? authApi,
  FakeTokenStorage? tokenStorage,
  MemoryLocalStore? localStore,
  Duration? syncInterval,
  FakeBarcodeScanner? barcodeScanner,
  bool cameraScanning = true,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(
          tokenStorage ?? FakeTokenStorage(access: 'a', refresh: 'r'),
        ),
        authApiProvider.overrideWithValue(authApi ?? FakeAuthApi()),
        // Never the real SharedPreferences (a platform channel) in a widget test.
        localStoreProvider.overrideWithValue(localStore ?? MemoryLocalStore()),
        // No background timer unless a test is about the timer (a pending timer fails a test).
        syncIntervalProvider.overrideWithValue(syncInterval),
        productsApiProvider.overrideWithValue(products ?? FakeProductsApi([])),
        inventoryApiProvider.overrideWithValue(inventory ?? FakeInventoryApi()),
        categoriesApiProvider.overrideWithValue(FakeCategoriesApi()),
        salesApiProvider.overrideWithValue(sales ?? FakeSalesApi(catalog: const [])),
        paymentMethodsApiProvider.overrideWithValue(paymentMethods ?? FakePaymentMethodsApi()),
        paymentsApiProvider.overrideWithValue(
          payments ??
              FakePaymentsApi(
                sales: sales ?? FakeSalesApi(catalog: const []),
                catalog: const [],
                options: paymentMethods ?? FakePaymentMethodsApi(),
              ),
        ),
        // No background timer unless a test is about it (a pending timer fails a test).
        paymentSummaryRefreshProvider.overrideWithValue(null),
        clipboardWriterProvider.overrideWithValue((text) async => copiedTexts?.add(text)),
        ussdLauncherProvider.overrideWithValue((code) async {
          dialedCodes?.add(code);
          return true;
        }),
        customersApiProvider.overrideWithValue(customers ?? FakeCustomersApi()),
        expensesApiProvider.overrideWithValue(expenses ?? FakeExpensesApi()),
        dashboardApiProvider.overrideWithValue(dashboard ?? FakeDashboardApi()),
        businessApiProvider.overrideWithValue(FakeBusinessApi()),
        textSharerProvider.overrideWithValue((text) async => sharedTexts?.add(text)),
        photoPickerProvider.overrideWithValue((photoPicker ?? FakePhotoPicker()).call),
        barcodeScannerProvider.overrideWithValue((barcodeScanner ?? FakeBarcodeScanner()).call),
        cameraScanningAvailableProvider.overrideWithValue(cameraScanning),
        fileSharerProvider.overrideWithValue(({
          required bytes,
          required filename,
          required mimeType,
          text,
        }) async {
          if (fileShareError != null) throw fileShareError;
          sharedFiles?.add(
            SharedFile(bytes: bytes, filename: filename, mimeType: mimeType, text: text),
          );
        }),
        // Loading the real font assets needs real (not faked) async; tests that build a PDF load
        // them once up front and hand them in.
        if (receiptFonts != null) receiptFontsProvider.overrideWith((ref) => receiptFonts),
      ],
      child: const ThyBusinessApp(),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}
