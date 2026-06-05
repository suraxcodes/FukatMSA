import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthService {
  static final _supabase = Supabase.instance.client;

  static Future<AuthResponse> signUp({required String email, required String password}) async {
    return await _supabase.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signIn({required String email, required String password}) async {
    return await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static User? get currentUser => _supabase.auth.currentUser;

  static Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  static bool get isPremium {
    final user = currentUser;
    if (user == null) return false;
    final metadata = user.userMetadata;
    return metadata != null && metadata['is_premium'] == true;
  }

  static Future<void> upgradeToPremium() async {
    final user = currentUser;
    if (user != null) {
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {'is_premium': true},
        ),
      );
    }
  }
}
