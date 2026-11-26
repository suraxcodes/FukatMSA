/// Authentication only — no entitlements.
///
/// ## Why the premium code is gone
///
/// The old service exposed `isPremium`, which read `user_metadata.is_premium`,
/// plus `upgradeToPremium()`, which called `updateUser(data: {'is_premium': true})`
/// **from the client**. Supabase lets a user write their own `user_metadata`,
/// so anyone with a session could grant themselves premium in one call. The
/// `PremiumScreen` had no payment step at all — it awaited two seconds and
/// toasted "Upgrade successful". Since the flag was also the only gate on the
/// interstitial ad, the net effect was: the paywall paid nothing and blocked
/// nobody.
///
/// Entitlements now live server-side only. If ads ever come back with a real
/// store (RevenueCat / Play Billing), the client must read a *read-only*
/// column (e.g. `profiles.is_pro` maintained by a webhook with RLS that denies
/// user writes), never `user_metadata`.
///
/// Auth is also optional now: if the build has no Supabase credentials, the
/// app runs in local-only mode instead of showing "Fatal Initialization Error".
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/errors.dart';
import '../core/log.dart';

class SupabaseAuthService {
  SupabaseAuthService._();

  static const String _tag = 'Auth';

  static bool _initialized = false;

  /// True when the client is usable. Everything must check this first.
  static bool get isAvailable => _initialized;

  /// Called from main(). Never throws: a bad/missing key disables cloud sync
  /// and leaves the app fully usable offline.
  static Future<bool> initialize() async {
    if (_initialized) return true;
    if (!AppConfig.hasSupabaseCredentials) {
      Log.w(_tag, 'no Supabase credentials — running in local-only mode');
      return false;
    }
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      _initialized = true;
      Log.i(_tag, 'Supabase ready');
      return true;
    } catch (e) {
      Log.e(_tag, 'Supabase init failed — cloud sync disabled', e);
      return false;
    }
  }

  static SupabaseClient get _client {
    if (!_initialized) {
      throw const AppError(
        AppErrorKind.unauthorized,
        'Cloud sync is not configured on this build.',
      );
    }
    return Supabase.instance.client;
  }

  static User? get currentUser =>
      _initialized ? Supabase.instance.client.auth.currentUser : null;

  static bool get isSignedIn => currentUser != null;

  static Stream<AuthState>? get authStateChanges =>
      _initialized ? Supabase.instance.client.auth.onAuthStateChange : null;

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signUp(email: email, password: password);
    } catch (e) {
      throw AppError.from(e, context: 'sign up');
    }
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw AppError.from(e, context: 'sign in');
    }
  }

  static Future<void> signInWithOtp({required String email}) async {
    try {
      await _client.auth.signInWithOtp(email: email);
    } catch (e) {
      throw AppError.from(e, context: 'send OTP');
    }
  }

  static Future<AuthResponse> verifyOTP({
    required String email,
    required String token,
    OtpType type = OtpType.magiclink,
  }) async {
    try {
      return await _client.auth.verifyOTP(
        type: type,
        email: email,
        token: token,
      );
    } catch (e) {
      throw AppError.from(e, context: 'verify OTP');
    }
  }

  static Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await _client.auth.signOut();
    } catch (e) {
      Log.w(_tag, 'sign out failed', e);
    }
  }
}
