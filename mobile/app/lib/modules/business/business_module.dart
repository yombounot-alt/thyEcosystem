import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/categories/presentation/categories_screen.dart';
import '../../features/customers/data/customer_models.dart';
import '../../features/customers/presentation/credits_overview_screen.dart';
import '../../features/customers/presentation/customer_detail_screen.dart';
import '../../features/customers/presentation/customer_form_screen.dart';
import '../../features/customers/presentation/customers_list_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/expenses/presentation/expense_form_screen.dart';
import '../../features/expenses/presentation/expenses_list_screen.dart';
import '../../features/inventory/presentation/stock_history_screen.dart';
import '../../features/inventory/presentation/stock_movement_screen.dart';
import '../../features/payments/data/payment_models.dart';
import '../../features/payments/presentation/choose_payment_screen.dart';
import '../../features/payments/presentation/declare_payment_screen.dart';
import '../../features/payments/presentation/payment_detail_screen.dart';
import '../../features/payments/presentation/payment_option_form_screen.dart';
import '../../features/payments/presentation/payment_options_screen.dart';
import '../../features/payments/presentation/payments_screen.dart';
import '../../features/pos/presentation/cart_screen.dart';
import '../../features/pos/presentation/payment_screen.dart';
import '../../features/pos/presentation/pos_screen.dart';
import '../../features/products/presentation/product_detail_screen.dart';
import '../../features/products/presentation/product_form_screen.dart';
import '../../features/products/presentation/products_list_screen.dart';
import '../../features/sales/presentation/pending_receipt_screen.dart';
import '../../features/sales/presentation/pending_sales_screen.dart';
import '../../features/sales/presentation/receipt_screen.dart';
import '../../features/sales/presentation/sales_history_screen.dart';
import '../../core/modules/app_module.dart';
import '../../features/payments/application/payments_providers.dart';
import 'business_more_section.dart';
import 'business_shell_banner.dart';

/// THY Business: till, stock, customers and credit, expenses, direct payments, dashboard.
class BusinessModule extends AppModule {
  const BusinessModule();

  @override
  String get id => 'business';

  @override
  ModuleTab get home => ModuleTab(
    path: '/dashboard',
    label: 'Accueil',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    screen: () => const DashboardScreen(),
  );

  @override
  List<ModuleTab> get tabs => [
    ModuleTab(
      path: '/pos',
      label: 'Caisse',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale,
      screen: () => const PosScreen(),
    ),
    ModuleTab(
      path: '/stock',
      label: 'Stock',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      screen: () => const ProductsListScreen(),
    ),
  ];

  @override
  List<RouteBase> get routes => [
    GoRoute(path: '/stock/history', builder: (context, state) => const StockHistoryScreen()),
    GoRoute(path: '/categories', builder: (context, state) => const CategoriesScreen()),
    GoRoute(path: '/customers', builder: (context, state) => const CustomersListScreen()),
    // '/customers/new' must stay above '/customers/:id'.
    GoRoute(path: '/customers/new', builder: (context, state) => const CustomerFormScreen()),
    GoRoute(
      path: '/customers/:id',
      builder: (context, state) => CustomerDetailScreen(customerId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (context, state) => CustomerFormScreen(customerId: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(path: '/credits', builder: (context, state) => const CreditsOverviewScreen()),
    GoRoute(path: '/expenses', builder: (context, state) => const ExpensesListScreen()),
    // '/expenses/new' has a different depth than '/expenses/:id/edit', so no ordering clash.
    GoRoute(path: '/expenses/new', builder: (context, state) => const ExpenseFormScreen()),
    GoRoute(
      path: '/expenses/:id/edit',
      builder: (context, state) => ExpenseFormScreen(expenseId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/pos/cart', builder: (context, state) => const CartScreen()),
    GoRoute(path: '/pos/payment', builder: (context, state) => const PaymentScreen()),
    // Direct payments (Orange Money / Mobile Money / merchant code), verified by the owner.
    GoRoute(
      path: '/pos/pay',
      builder:
          (context, state) => ChoosePaymentScreen(
            customer: state.extra is Customer ? state.extra as Customer : null,
          ),
    ),
    GoRoute(
      path: '/pos/pay/declare/:id',
      builder:
          (context, state) => DeclarePaymentScreen(
            paymentId: state.pathParameters['id']!,
            initial: state.extra is ManualPayment ? state.extra as ManualPayment : null,
            fromTill: state.uri.queryParameters['till'] == '1',
          ),
    ),
    GoRoute(
      path: '/payments',
      builder:
          (context, state) => PaymentsScreen(initialStatus: state.uri.queryParameters['status']),
    ),
    GoRoute(
      path: '/payments/:id',
      builder:
          (context, state) => PaymentDetailScreen(
            paymentId: state.pathParameters['id']!,
            fromTill: state.uri.queryParameters['till'] == '1',
          ),
    ),
    GoRoute(
      path: '/settings/payment-methods',
      builder: (context, state) => const PaymentOptionsScreen(),
    ),
    // '/new' must stay above '/:id'.
    GoRoute(
      path: '/settings/payment-methods/new',
      builder: (context, state) => const PaymentOptionFormScreen(),
    ),
    GoRoute(
      path: '/settings/payment-methods/:id',
      builder: (context, state) => PaymentOptionFormScreen(optionId: state.pathParameters['id']),
    ),
    GoRoute(path: '/sales', builder: (context, state) => const SalesHistoryScreen()),
    // '/sales/pending' must stay above '/sales/:id'.
    GoRoute(path: '/sales/pending', builder: (context, state) => const PendingSalesScreen()),
    GoRoute(
      path: '/sales/pending/:id',
      builder:
          (context, state) => PendingReceiptScreen(
            pendingId: state.pathParameters['id']!,
            change: double.tryParse(state.uri.queryParameters['change'] ?? '') ?? 0,
          ),
    ),
    GoRoute(
      path: '/sales/:id',
      builder:
          (context, state) => ReceiptScreen(
            saleId: state.pathParameters['id']!,
            change: double.tryParse(state.uri.queryParameters['change'] ?? '') ?? 0,
          ),
    ),
    // '/products/new' must stay above '/products/:id'.
    GoRoute(path: '/products/new', builder: (context, state) => const ProductFormScreen()),
    GoRoute(
      path: '/products/:id',
      builder: (context, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (context, state) => ProductFormScreen(productId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'stock',
          builder: (context, state) => StockMovementScreen(productId: state.pathParameters['id']!),
        ),
      ],
    ),
  ];

  @override
  Widget moreSection() => const BusinessMoreSection();

  @override
  Widget? shellBanner() => const BusinessShellBanner();

  @override
  int moreBadge(WidgetRef ref) => ref.watch(paymentsToVerifyProvider);
}
