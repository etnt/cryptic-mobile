/// Initialize Session Use Case.
///
/// Handles X3DH session establishment with a peer.
library;

import '../../data/engine/cryptic_engine.dart';
import 'use_case.dart';

/// Parameters for initializing a session.
class InitializeSessionParams {
  /// Creates initialize session parameters.
  const InitializeSessionParams({
    required this.peerUsername,
  });

  /// The peer's username.
  final String peerUsername;
}

/// Result of session initialization.
class SessionInitResult {
  /// Creates a session initialization result.
  const SessionInitResult({
    required this.peerUsername,
    required this.isNewSession,
  });

  /// The peer username the session was established with.
  final String peerUsername;

  /// Whether this is a new session or an existing one was loaded.
  final bool isNewSession;
}

/// Use case for initializing a session with a peer.
///
/// This use case:
/// 1. Checks if a session already exists
/// 2. If not, requests the peer's key bundle
/// 3. Triggers X3DH session establishment
///
/// Note: Session establishment is asynchronous - the actual X3DH
/// handshake completes when the server responds with the key bundle.
///
/// Example:
/// ```dart
/// final useCase = InitializeSessionUseCase(engine);
/// final result = await useCase(InitializeSessionParams(
///   peerUsername: 'bob',
/// ));
///
/// result.fold(
///   onSuccess: (result) => print('Session ready: ${result.isNewSession}'),
///   onError: (error, _) => print('Failed: $error'),
/// );
/// ```
class InitializeSessionUseCase
    implements UseCase<InitializeSessionParams, SessionInitResult> {
  /// Creates an InitializeSessionUseCase.
  InitializeSessionUseCase(this._engine);

  final CrypticEngine _engine;

  @override
  Future<UseCaseResult<SessionInitResult>> call(
    InitializeSessionParams params,
  ) async {
    try {
      // Validate input
      if (params.peerUsername.isEmpty) {
        return const UseCaseError('Peer username cannot be empty');
      }

      // Check engine state
      if (!_engine.isInitialized) {
        return const UseCaseError('Engine not initialized');
      }
      if (!_engine.isConnected) {
        return const UseCaseError('Not connected to server');
      }

      // Check if session already exists
      final hasSession = _engine.state.sessions.containsKey(params.peerUsername);

      if (hasSession) {
        // Session exists
        return UseCaseSuccess(SessionInitResult(
          peerUsername: params.peerUsername,
          isNewSession: false,
        ),);
      }

      // Request key bundle to trigger X3DH
      // Note: Actual session establishment happens asynchronously
      // when the key bundle response is received
      await _engine.requestKeyBundle(params.peerUsername);

      return UseCaseSuccess(SessionInitResult(
        peerUsername: params.peerUsername,
        isNewSession: true,
      ),);
    } catch (e) {
      return UseCaseError('Failed to initialize session', e);
    }
  }
}
