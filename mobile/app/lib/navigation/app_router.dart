import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'module_registry.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/onboarding_screen.dart';
import '../features/auth/presentation/otp_verify_screen.dart';
import '../features/auth/presentation/phone_screen.dart';
import '../features/auth/presentation/profile_name_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/business/presentation/business_create_screen.dart';
import '../features/business/presentation/business_settings_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/subscription/presentation/subscription_screen.dart';
import '../features/team/presentation/invite_member_screen.dart';
import '../features/team/presentation/received_invitations.dart';
import '../features/team/presentation/team_screen.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/shell/presentation/more_screen.dart';

const _publicRoutes = {'/onboarding', '/phone', '/otp-verify'};

/// Screens that only make sense before a session is fully set up.
const _preSessionRoutes = {..._publicRoutes, '/splash', '/profile-name', '/business/create'};

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  final modules = ref.watch(appModulesProvider);
  final navigation = ref.watch(navigationProvider);

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
          for (final tab in navigation.tabs)
            if (tab.path != '/more')
              GoRoute(path: tab.path, builder: (context, state) => tab.screen()),
          GoRoute(path: '/more', builder: (context, state) => const MoreScreen()),
        ],
      ),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
      GoRoute(path: '/team', builder: (context, state) => const TeamScreen()),
      GoRoute(path: '/team/invite', builder: (context, state) => const InviteMemberScreen()),
      GoRoute(path: '/invitations', builder: (context, state) => const ReceivedInvitationsScreen()),
      GoRoute(
        path: '/settings/subscription',
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/settings/business',
        builder: (context, state) => const BusinessSettingsScreen(),
      ),
      // An additional business for an account that already has one ('/business/create' is the
      // last step of the first sign-in, and redirects once a business exists).
      GoRoute(
        path: '/businesses/new',
        builder: (context, state) => const BusinessCreateScreen(another: true),
      ),
      for (final module in modules) ...module.routes,
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
