/// Authentication state provider.
///
/// Manages the authentication flow including:
/// - Username/passphrase entry
/// - Key generation/loading
/// - Unlock state
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Authentication state.
enum AuthState {
  /// Not authenticated - needs login.
  unauthenticated,

  /// Currently authenticating.
  authenticating,

  /// Authenticated and ready.
  authenticated,

  /// Needs first-time setup (no keys exist).
  needsSetup,

  /// Authentication failed.
  failed,
}

/// Authentication status with optional error message.
class AuthStatus {
  /// Creates an authentication status.
  const AuthStatus({
    required this.state,
    this.username,
    this.error,
  });

  /// Initial unauthenticated status.
  static const initial = AuthStatus(state: AuthState.unauthenticated);

  /// The current authentication state.
  final AuthState state;

  /// The authenticated username (if authenticated).
  final String? username;

  /// Error message (if failed).
  final String? error;

  /// Whether currently authenticated.
  bool get isAuthenticated => state == AuthState.authenticated;

  /// Whether authentication is in progress.
  bool get isAuthenticating => state == AuthState.authenticating;

  /// Whether setup is needed.
  bool get needsSetup => state == AuthState.needsSetup;

  /// Copy with updated fields.
  AuthStatus copyWith({
    AuthState? state,
    String? username,
    String? error,
    bool clearError = false,
  }) {
    return AuthStatus(
      state: state ?? this.state,
      username: username ?? this.username,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for authentication state.
class AuthNotifier extends StateNotifier<AuthStatus> {
  /// Creates an auth notifier.
  AuthNotifier() : super(AuthStatus.initial);

  /// Attempt to authenticate with username and passphrase.
  Future<bool> authenticate({
    required String username,
    required String passphrase,
  }) async {
    state = state.copyWith(
      state: AuthState.authenticating,
      clearError: true,
    );

    try {
      // TODO: Implement actual authentication logic
      // - Check if keys exist
      // - Load and decrypt keys with passphrase
      // - Initialize engine

      // Simulate authentication delay
      await Future.delayed(const Duration(milliseconds: 500));

      state = AuthStatus(
        state: AuthState.authenticated,
        username: username,
      );

      return true;
    } catch (e) {
      state = AuthStatus(
        state: AuthState.failed,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Set up new user with username and passphrase.
  Future<bool> setup({
    required String username,
    required String passphrase,
  }) async {
    state = state.copyWith(
      state: AuthState.authenticating,
      clearError: true,
    );

    try {
      // TODO: Implement actual setup logic
      // - Generate new identity keys
      // - Encrypt and save keys with passphrase
      // - Initialize engine

      // Simulate setup delay
      await Future.delayed(const Duration(milliseconds: 500));

      state = AuthStatus(
        state: AuthState.authenticated,
        username: username,
      );

      return true;
    } catch (e) {
      state = AuthStatus(
        state: AuthState.failed,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Log out and clear authentication state.
  void logout() {
    state = AuthStatus.initial;
  }

  /// Check if user needs initial setup.
  Future<void> checkAuthState() async {
    // TODO: Check if identity keys exist
    // If not, set state to needsSetup
    state = state.copyWith(state: AuthState.unauthenticated);
  }
}

/// Provider for authentication state.
final authProvider = StateNotifierProvider<AuthNotifier, AuthStatus>((ref) {
  return AuthNotifier();
});

/// Provider for whether user is authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final auth = ref.watch(authProvider);
  return auth.isAuthenticated;
});

/// Provider for current username (if authenticated).
final currentUsernameProvider = Provider<String?>((ref) {
  final auth = ref.watch(authProvider);
  return auth.username;
});
