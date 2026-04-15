/// Connect Use Case.
///
/// Handles connecting to the Cryptic server.
library;

import '../../data/engine/cryptic_engine.dart';
import '../../data/engine/engine_state.dart';
import 'use_case.dart';

/// Parameters for connecting to the server.
class ConnectParams {
  /// Creates connect parameters.
  const ConnectParams({
    this.autoUploadKeys = true,
    this.requestUserList = true,
  });

  /// Whether to automatically upload keys after connecting.
  final bool autoUploadKeys;

  /// Whether to request the user list after connecting.
  final bool requestUserList;
}

/// Result of connection attempt.
class ConnectResult {
  /// Creates a connect result.
  const ConnectResult({
    required this.status,
    this.userCount,
  });

  /// The resulting connection status.
  final ConnectionStatus status;

  /// Number of users online (if user list was requested).
  final int? userCount;
}

/// Use case for connecting to the server.
///
/// This use case:
/// 1. Initializes the engine if needed
/// 2. Establishes WebSocket connection
/// 3. Optionally uploads identity keys
/// 4. Optionally requests user list
///
/// Example:
/// ```dart
/// final useCase = ConnectUseCase(engine);
/// final result = await useCase(ConnectParams());
///
/// result.fold(
///   onSuccess: (result) => print('Connected: ${result.status}'),
///   onError: (error, _) => print('Failed: $error'),
/// );
/// ```
class ConnectUseCase implements UseCase<ConnectParams, ConnectResult> {
  /// Creates a ConnectUseCase.
  ConnectUseCase(this._engine);

  final CrypticEngine _engine;

  @override
  Future<UseCaseResult<ConnectResult>> call(ConnectParams params) async {
    try {
      // Initialize engine if needed
      if (!_engine.isInitialized) {
        await _engine.initialize();
      }

      // Connect to server
      await _engine.connect();

      // Return success
      return UseCaseSuccess(ConnectResult(
        status: _engine.state.connectionStatus,
      ),);
    } catch (e) {
      return UseCaseError('Failed to connect', e);
    }
  }
}

/// Use case for disconnecting from the server.
class DisconnectUseCase implements NoInputUseCase<void> {
  /// Creates a DisconnectUseCase.
  DisconnectUseCase(this._engine);

  final CrypticEngine _engine;

  @override
  Future<UseCaseResult<void>> call() async {
    try {
      await _engine.disconnect();
      return const UseCaseSuccess(null);
    } catch (e) {
      return UseCaseError('Failed to disconnect', e);
    }
  }
}
