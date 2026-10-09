/// Send file use case.
library;

import 'dart:typed_data';

import '../../data/engine/cryptic_engine.dart';
import '../../data/engine/payload_codec.dart';
import 'use_case.dart';

class SendFileParams {
  const SendFileParams({
    required this.toUser,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final String toUser;
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class SendFileUseCase implements UseCase<SendFileParams, String> {
  SendFileUseCase(this._engine);

  final CrypticEngine _engine;

  @override
  Future<UseCaseResult<String>> call(SendFileParams params) async {
    if (params.toUser.isEmpty) {
      return const UseCaseError('Recipient username cannot be empty');
    }
    if (params.bytes.isEmpty ||
        params.bytes.length > AttachmentLimits.maxFileBytes) {
      return const UseCaseError('Attachment must be no larger than 10 MB');
    }
    if (!_engine.isInitialized) {
      return const UseCaseError('Engine not initialized');
    }
    if (!_engine.isConnected) {
      return const UseCaseError('Not connected to server');
    }
    try {
      final id = await _engine.sendFile(
        params.toUser,
        params.bytes,
        params.fileName,
        params.mimeType,
      );
      return UseCaseSuccess(id);
    } catch (error) {
      return UseCaseError('Failed to send attachment', error);
    }
  }
}
