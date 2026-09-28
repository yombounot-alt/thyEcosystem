import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/offline/offline_providers.dart';
import '../../../core/providers.dart';
import '../data/auth_api.dart';
import '../data/auth_models.dart';
import 'auth_state.dart';

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(dioProvider)));

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Fire-and-forget: the splash screen stays up (via router redirect) until this resolves.
    _restoreSession();
    return const AuthState();
  }

  Future<void> _restoreSession() async {
    final token = await ref.read(tokenStorageProvider).readAccessToken();
    if (token == null) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      _apply(await _resolveProfile());
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        // The server itself says this session is over.
        await _endSession();
      } else {
        // No network / server down: keep the session, let the user retry. Being offline must
        // never log anyone out (logging back in needs the network).
        state = const AuthState(status: AuthStatus.unreachable);
      }
    } catch (_) {
      state = const AuthState(status: AuthStatus.unreachable);
    }
  }

  /// The profile, with an active business picked when the user has some but none is active (fresh
  /// session, new device, or removed from the business they were working in): the oldest one. The
  /// user can switch from the "Plus" tab.
  Future<UserProfile> _resolveProfile() async {
    var profile = await ref.read(authApiProvider).me();
    if (profile.activeBusinessId == null && profile.businesses.isNotEmpty) {
      final token = await ref.read(authApiProvider).activateBusiness(profile.businesses.first.id);
      await ref.read(tokenStorageProvider).saveAccessToken(token);
      profile = await ref.read(authApiProvider).me();
    }
    return profile;
  }

  void _apply(UserProfile profile) {
    // Cached answers belong to this user + business only.
    ref.read(offlineScopeProvider.notifier).set('${profile.id}:${profile.activeBusinessId}');
    state = AuthState(status: _statusFor(profile), profile: profile);
  }

  AuthStatus _statusFor(UserProfile profile) {
    if (!profile.hasName) return AuthStatus.needsName;
    return profile.activeBusinessId != null ? AuthStatus.authenticated : AuthStatus.needsBusiness;
  }

  /// Retry from the "cannot reach the server" splash.
  Future<void> retry() async {
    state = const AuthState();
    await _restoreSession();
  }

  Future<void> _endSession() async {
    await ref.read(tokenStorageProvider).clear();
    ref.read(offlineScopeProvider.notifier).set(null);
    await ref.read(offlineCacheProvider).clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> requestOtp({required String phone}) {
    return ref.read(authApiProvider).requestOtp(phone: phone);
  }

  Future<void> verifyOtp({required String phone, required String code}) async {
    final tokens = await ref.read(authApiProvider).verifyOtp(phone: phone, code: code);
    await ref
        .read(tokenStorageProvider)
        .saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
    await _loadProfile();
  }

  /// First sign-in: the name is asked once, then the flow goes on (business creation).
  Future<void> saveName(String fullName) async {
    await ref.read(authApiProvider).updateFullName(fullName.trim());
    await _loadProfile();
  }

  /// Called by the business-creation flow once a business has been created: the server issued an
  /// access token that carries the new business (the refresh token of the session is unchanged).
  Future<void> onBusinessCreated(String accessToken) async {
    await ref.read(tokenStorageProvider).saveAccessToken(accessToken);
    await _loadProfile();
  }

  /// Works in another business from now on (the user must be a member: the server checks). The
  /// offline cache is scoped per business, so the screens reload that business's data.
  Future<void> switchBusiness(String businessId) async {
    final token = await ref.read(authApiProvider).activateBusiness(businessId);
    await ref.read(tokenStorageProvider).saveAccessToken(token);
    await _loadProfile();
  }

  /// Re-reads the profile after a change made elsewhere (name, role, a business joined). Unlike the
  /// start-up load, a failure here keeps the current state: the change will show up next time.
  Future<void> refreshProfile() async {
    try {
      _apply(await _resolveProfile());
    } catch (_) {
      // Keep what is on screen.
    }
  }

  Future<void> logout() async {
    final storage = ref.read(tokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await ref.read(authApiProvider).logout(refreshToken);
      } catch (_) {
        // Best-effort server-side revocation; clearing local tokens below is what matters.
      }
    }
    await _endSession();
  }
}
