import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_service.dart';

class AuthResult {
  const AuthResult({this.email, this.message = ''});

  final String? email;
  final String message;
}

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  Future<String?> restoreSession() async {
    await _ensureReady();
    return Supabase.instance.client.auth.currentUser?.email;
  }

  Future<AuthResult> signIn(String email, String password) async {
    await _ensureReady();
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return AuthResult(email: response.user?.email);
  }

  Future<AuthResult> signUp(String email, String password) async {
    await _ensureReady();
    final response = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
    );
    if (response.session == null) {
      return const AuthResult(
        message:
            'Registration successful. Check your email to verify your account.',
      );
    }
    return AuthResult(email: response.user?.email);
  }

  Future<void> signOut() async {
    await _ensureReady();
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _ensureReady() async {
    await SyncService.instance.initialize();
    if (!SyncService.instance.isReady) {
      throw StateError('Supabase is not configured for this build.');
    }
  }
}
