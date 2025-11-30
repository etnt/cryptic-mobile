/// Send Message Use Case.
///
/// Handles sending encrypted messages to peers through the CrypticEngine.
library;

import '../../data/engine/cryptic_engine.dart';
import 'use_case.dart';

/// Parameters for sending a message.
class SendMessageParams {
  /// Creates send message parameters.
  const SendMessageParams({
    required this.toUser,
    required this.plaintext,
  });

  /// The recipient username.
  final String toUser;

  /// The message plaintext.
  final String plaintext;
}

/// Use case for sending an encrypted message.
///
/// This use case:
/// 1. Checks if a session exists with the recipient
/// 2. If no session, initiates X3DH key agreement
/// 3. Encrypts the message using Double Ratchet
/// 4. Sends the encrypted message via WebSocket
///
/// Example:
/// ```dart
/// final useCase = SendMessageUseCase(engine);
/// final result = await useCase(SendMessageParams(
///   toUser: 'bob',
///   plaintext: 'Hello Bob!',
/// ));
///
/// result.fold(
///   onSuccess: (_) => print('Message sent'),
///   onError: (error, _) => print('Failed: $error'),
/// );
/// ```
class SendMessageUseCase implements UseCase<SendMessageParams, void> {
  /// Creates a SendMessageUseCase.
  SendMessageUseCase(this._engine);

  final CrypticEngine _engine;

  @override
  Future<UseCaseResult<void>> call(SendMessageParams params) async {
    try {
      // Validate input
      if (params.toUser.isEmpty) {
        return const UseCaseError('Recipient username cannot be empty');
      }
      if (params.plaintext.isEmpty) {
        return const UseCaseError('Message cannot be empty');
      }

      // Check engine state
      if (!_engine.isInitialized) {
        return const UseCaseError('Engine not initialized');
      }
      if (!_engine.isConnected) {
        return const UseCaseError('Not connected to server');
      }

      // Send message through engine
      await _engine.sendMessage(params.toUser, params.plaintext);

      return const UseCaseSuccess(null);
    } catch (e) {
      return UseCaseError('Failed to send message', e);
    }
  }
}
