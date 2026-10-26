import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

abstract interface class AuthBackend {
  AuthUser? get currentUser;
  Stream<AuthUser?> get authStateChanges;
  Future<AuthUser?> signIn({required String email, required String password});
  Future<AuthUser?> signUp({required String email, required String password});
  Future<void> signOut();
}

abstract interface class AuthGateway {
  AuthUser? get currentUser;
  Stream<AuthUser?> get authStateChanges;
  Future<AuthUser?> signIn({required String email, required String password});
  Future<AuthUser?> signUp({required String email, required String password});
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  factory SupabaseAuthGateway({required SupabaseClient client}) =>
      SupabaseAuthGateway.fromBackend(_SupabaseAuthBackend(client.auth));

  SupabaseAuthGateway.fromBackend(this._backend);

  final AuthBackend _backend;

  @override
  AuthUser? get currentUser => _backend.currentUser;

  @override
  Stream<AuthUser?> get authStateChanges => _backend.authStateChanges;

  @override
  Future<AuthUser?> signIn({required String email, required String password}) =>
      _backend.signIn(email: email, password: password);

  @override
  Future<AuthUser?> signUp({required String email, required String password}) =>
      _backend.signUp(email: email, password: password);

  @override
  Future<void> signOut() => _backend.signOut();
}

class DemoAuthGateway implements AuthGateway {
  static const demoUserId = '00000000-0000-4000-8000-000000000001';

  final StreamController<AuthUser?> _states =
      StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Stream<AuthUser?> get authStateChanges => _states.stream;

  @override
  Future<AuthUser?> signIn({required String email, required String password}) {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const FormatException('Email och lösenord krävs.');
    }
    return _setUser(const AuthUser(id: demoUserId, email: 'demo@falt.local'));
  }

  Future<AuthUser> continueDemo() =>
      _setUser(const AuthUser(id: demoUserId));

  @override
  Future<AuthUser?> signUp({required String email, required String password}) =>
      signIn(email: email, password: password);

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _states.add(null);
  }

  Future<AuthUser> _setUser(AuthUser user) async {
    _currentUser = user;
    _states.add(user);
    return user;
  }
}

class _SupabaseAuthBackend implements AuthBackend {
  _SupabaseAuthBackend(this._auth);

  final GoTrueClient _auth;

  @override
  AuthUser? get currentUser => _fromSupabaseUser(_auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges => _auth.onAuthStateChange.map(
        (state) => _fromSupabaseUser(state.session?.user),
      );

  @override
  Future<AuthUser?> signIn({required String email, required String password}) async {
    final response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );
    return _fromSupabaseUser(response.user);
  }

  @override
  Future<AuthUser?> signUp({required String email, required String password}) async {
    final response = await _auth.signUp(email: email, password: password);
    return _fromSupabaseUser(response.user);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static AuthUser? _fromSupabaseUser(User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);
}

String sanitizeAuthError(Object error) {
  return 'Inloggningen kunde inte genomföras. Kontrollera uppgifterna och försök igen.';
}
