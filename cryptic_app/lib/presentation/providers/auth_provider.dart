/// Authentication state provider.
///
/// Manages the authentication flow including:
/// - Username/passphrase entry
/// - Key generation/loading
/// - mTLS connection to server
/// - Unlock state
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/engine/cryptic_engine.dart';
import '../../data/services/authentication_service.dart';

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
  AuthNotifier({
    AuthenticationService? authService,
  })  : _authService = authService ?? AuthenticationService(),
        super(AuthStatus.initial);

  final AuthenticationService _authService;

  /// The currently connected CrypticEngine (if authenticated).
  CrypticEngine? _engine;

  /// Get the current engine.
  CrypticEngine? get engine => _engine;

  /// Server configuration for connection.
  ServerConnectionConfig _serverConfig = ServerConnectionConfig.localhost;

  /// Update server configuration.
  void setServerConfig(ServerConnectionConfig config) {
    _serverConfig = config;
  }

  /// Attempt to authenticate with username and passphrase.
  Future<bool> authenticate({
    required String username,
    required String passphrase,
    String? serverHost,
    int? serverPort,
  }) async {
    state = state.copyWith(
      state: AuthState.authenticating,
      clearError: true,
    );

    try {
      // Use provided server config or default
      final config = (serverHost != null && serverPort != null)
          ? ServerConnectionConfig(host: serverHost, port: serverPort)
          : _serverConfig;

      final result = await _authService.authenticate(
        username: username,
        passphrase: passphrase,
        serverConfig: config,
      );

      if (result.success && result.engine != null) {
        _engine = result.engine;
        state = AuthStatus(
          state: AuthState.authenticated,
          username: username,
        );
        return true;
      } else {
        state = AuthStatus(
          state: AuthState.failed,
          error: result.error ?? 'Authentication failed',
        );
        return false;
      }
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
    String? serverHost,
    int? serverPort,
  }) async {
    state = state.copyWith(
      state: AuthState.authenticating,
      clearError: true,
    );

    try {
      // Use provided server config or default
      final config = (serverHost != null && serverPort != null)
          ? ServerConnectionConfig(host: serverHost, port: serverPort)
          : _serverConfig;

      final result = await _authService.setup(
        username: username,
        passphrase: passphrase,
        serverConfig: config,
      );

      if (result.success && result.engine != null) {
        _engine = result.engine;
        state = AuthStatus(
          state: AuthState.authenticated,
          username: username,
        );
        return true;
      } else {
        state = AuthStatus(
          state: AuthState.failed,
          error: result.error ?? 'Setup failed',
        );
        return false;
      }
    } catch (e) {
      state = AuthStatus(
        state: AuthState.failed,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Log out and clear authentication state.
  Future<void> logout() async {
    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
    }
    state = AuthStatus.initial;
  }

  /// Check if user needs initial setup.
  Future<void> checkAuthState() async {
    final hasCerts = await _authService.hasCertificates();
    if (!hasCerts) {
      state = state.copyWith(
        state: AuthState.needsSetup,
        error: 'No certificates found',
      );
      return;
    }

    final hasKeys = await _authService.hasIdentityKeys();
    if (!hasKeys) {
      state = state.copyWith(state: AuthState.needsSetup);
    } else {
      state = state.copyWith(state: AuthState.unauthenticated);
    }
  }
}

/// Provider for authentication state.
final authProvider = StateNotifierProvider<AuthNotifier, AuthStatus>((ref) {
  return AuthNotifier();
});

/// Provider for the authenticated engine.
///
/// Returns the CrypticEngine if authenticated, null otherwise.
final authenticatedEngineProvider = Provider<CrypticEngine?>((ref) {
  final authNotifier = ref.watch(authProvider.notifier);
  final authStatus = ref.watch(authProvider);
  
  if (authStatus.isAuthenticated) {
    return authNotifier.engine;
  }
  return null;
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
