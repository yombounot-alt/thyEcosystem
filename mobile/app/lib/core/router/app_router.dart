import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/otp_verify_screen.dart';
import '../../features/auth/presentation/phone_screen.dart';
import '../../features/auth/presentation/profile_name_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/business/presentation/business_create_screen.dart';
import '../../features/categories/presentation/categories_screen.dart';
import '../../features/customers/presentation/credits_overview_screen.dart';
import '../../features/customers/presentation/customer_detail_screen.dart';
import '../../features/customers/presentation/customer_form_screen.dart';
import '../../features/customers/presentation/customers_list_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/expenses/presentation/expense_form_screen.dart';
import '../../features/expenses/presentation/expenses_list_screen.dart';
import '../../features/inventory/presentation/stock_history_screen.dart';
import '../../features/inventory/presentation/stock_movement_screen.dart';
import '../../features/customers/data/customer_models.dart';
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
import '../../features/shell/presentation/app_shell.dart';
import '../../features/shell/presentation/more_screen.dart';

const _publicRoutes = {'/onboarding', '/phone', '/otp-verify'};

/// Screens that only make sense before a session is fully set up.
const _preSessionRoutes = {..._publicRoutes, '/splash', '/profile-name', '/business/create'};

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) => _redirect(authState, state),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/phone', builder: (context, state) => const PhoneScreen()),
      GoRoute(path: '/profile-name', builder: (context, state) => const ProfileNameScreen()),
      GoRoute(
        path: '/otp-verify',
        builder:
            (context, state) => OtpVerifyScreen(phone: state.uri.queryParameters['phone'] ?? ''),
      ),
      GoRoute(path: '/business/create', builder: (context, state) => const BusinessCreateScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/pos', builder: (context, state) => const PosScreen()),
          GoRoute(path: '/stock', builder: (context, state) => const ProductsListScreen()),
          GoRoute(path: '/more', builder: (context, state) => const MoreScreen()),
        ],
      ),
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
            builder:
                (context, state) => CustomerFormScreen(customerId: state.pathParameters['id']!),
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
            builder:
                (context, state) => StockMovementScreen(productId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});

String? _redirect(AuthState authState, GoRouterState state) {
  final location = state.matchedLocation;

  switch (authState.status) {
    case AuthStatus.unknown:
    case AuthStatus.unreachable:
      return location == '/splash' ? null : '/splash';
    case AuthStatus.unauthenticated:
      if (location == '/splash') return '/onboarding';
      return _publicRoutes.contains(location) ? null : '/onboarding';
    case AuthStatus.needsName:
      return location == '/profile-name' ? null : '/profile-name';
    case AuthStatus.needsBusiness:
      return location == '/business/create' ? null : '/business/create';
    case AuthStatus.authenticated:
      return _preSessionRoutes.contains(location) ? '/dashboard' : null;
  }
}
