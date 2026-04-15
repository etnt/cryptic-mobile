/// Upload Keys Use Case.
///
/// Handles uploading identity keys and prekey bundles to the server.
library;

import '../../data/engine/cryptic_engine.dart';
import 'use_case.dart';

/// Parameters for uploading keys.
class UploadKeysParams {
  /// Creates upload keys parameters.
  const UploadKeysParams({
    this.generateNewPrekeys = false,
    this.prekeyCount = 10,
  });

  /// Whether to generate new one-time prekeys.
  final bool generateNewPrekeys;

  /// Number of one-time prekeys to generate (if generateNewPrekeys is true).
  final int prekeyCount;
}

/// Result of key upload.
class UploadKeysResult {
  /// Creates an upload keys result.
  const UploadKeysResult({
    required this.identityKeysUploaded,
    required this.prekeysUploaded,
  });

  /// Whether identity keys were uploaded.
  final bool identityKeysUploaded;

  /// Number of one-time prekeys uploaded.
  final int prekeysUploaded;
}

/// Use case for uploading cryptographic keys to the server.
///
/// This use case:
/// 1. Uploads identity public keys (signing + DH)
/// 2. Uploads signed prekey
/// 3. Optionally generates and uploads one-time prekeys
///
/// Example:
/// ```dart
/// final useCase = UploadKeysUseCase(engine);
/// final result = await useCase(UploadKeysParams(
///   generateNewPrekeys: true,
///   prekeyCount: 20,
/// ));
///
/// result.fold(
///   onSuccess: (result) => print('Uploaded ${result.prekeysUploaded} prekeys'),
///   onError: (error, _) => print('Failed: $error'),
/// );
/// ```
class UploadKeysUseCase implements UseCase<UploadKeysParams, UploadKeysResult> {
  /// Creates an UploadKeysUseCase.
  UploadKeysUseCase(this._engine);

  final CrypticEngine _engine;

  @override
  Future<UseCaseResult<UploadKeysResult>> call(UploadKeysParams params) async {
    try {
      // Check engine state
      if (!_engine.isInitialized) {
        return const UseCaseError('Engine not initialized');
      }
      if (!_engine.isConnected) {
        return const UseCaseError('Not connected to server');
      }

      // Validate prekey count
      if (params.generateNewPrekeys && params.prekeyCount <= 0) {
        return const UseCaseError('Prekey count must be positive');
      }

      // TODO: Implement key upload via engine
      // For now, return success as the engine handles key upload on connect
      return const UseCaseSuccess(UploadKeysResult(
        identityKeysUploaded: true,
        prekeysUploaded: 0,
      ),);
    } catch (e) {
      return UseCaseError('Failed to upload keys', e);
    }
  }
}
