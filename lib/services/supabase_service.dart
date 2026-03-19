import 'package:supabase_flutter/supabase_flutter.dart';

/// Static service for Supabase authentication and profile access.
class SupabaseService {
  static const _supabaseUrl = 'https://rdfwekkbpsdwzytbttlk.supabase.co';
  static const _supabaseAnonKey = 'sb_publishable_Qcl9dCHY5RVt3DPasp3IlQ_6DxmHGFo';
  static const _redirectUrl = 'io.supabase.papersuitecase://login-callback';

  /// Initialize Supabase. Call once at app startup.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  /// The Supabase client instance.
  static SupabaseClient get client => Supabase.instance.client;

  /// The currently authenticated user, or null.
  static User? get currentUser => client.auth.currentUser;

  /// The current auth session, or null.
  static Session? get currentSession => client.auth.currentSession;

  /// Whether a user is currently logged in.
  static bool get isLoggedIn => currentUser != null;

  /// Stream of auth state changes.
  static Stream<AuthState> get authStateChanges =>
      client.auth.onAuthStateChange;

  /// Sign up with email and password.
  static Future<AuthResponse> signUpWithEmail(
      String email, String password) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
  }

  /// Sign in with email and password.
  static Future<AuthResponse> signInWithEmail(
      String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign in with Google OAuth.
  static Future<void> signInWithGoogle() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _redirectUrl,
    );
  }

  /// Sign in with GitHub OAuth.
  static Future<void> signInWithGitHub() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: _redirectUrl,
    );
  }

  /// Sign out the current user.
  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Fetch the current user's profile from the profiles table.
  static Future<Map<String, dynamic>?> getProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    return response;
  }
}
