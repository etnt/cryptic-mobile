/// Message processor for handling incoming server messages.
///
/// Routes incoming WebSocket messages to appropriate handlers,
/// managing decryption, session creation, and event emission.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../crypto/ratchet/ratchet_message.dart';
import '../crypto/x3dh/x3dh_engine.dart';
import '../network/protocol/protocol_codec.dart';
import '../network/protocol/server_messages.dart';
import '../storage/repositories/key_repository.dart';
import 'engine_state.dart';
import 'session_manager.dart';

/// Result of processing an incoming message.
sealed class ProcessingResult {}

/// Message was processed successfully.
class ProcessingSuccess extends ProcessingResult {
  /// Creates a success result.
  ProcessingSuccess({this.event});

  /// Optional event to emit to UI.
  final EngineEvent? event;
}

/// Message processing failed.
class ProcessingFailure extends ProcessingResult {
  /// Creates a failure result.
  ProcessingFailure(this.error, [this.cause]);

  /// Error message.
  final String error;

  /// Underlying cause.
  final Object? cause;
}

/// Message requires further action.
class ProcessingPending extends ProcessingResult {
  /// Creates a pending result.
  ProcessingPending(this.action);

  /// Description of pending action.
  final String action;
}

/// Processes incoming server messages.
///
/// Handles:
/// - Incoming encrypted messages (X3DH and ratchet)
/// - Key bundle responses
/// - User list updates
/// - Message acknowledgments
/// - Error messages
class MessageProcessor {
  /// Creates a message processor.
  MessageProcessor({
    required SessionManager sessionManager,
    required KeyRepository keyRepository,
    X3dhEngine? x3dhEngine,
  })  : _sessionManager = sessionManager,
        _keyRepository = keyRepository,
        _x3dhEngine = x3dhEngine ?? X3dhEngine();

  final SessionManager _sessionManager;
  final KeyRepository _keyRepository;
  final X3dhEngine _x3dhEngine;

  final _eventController = StreamController<EngineEvent>.broadcast();

  /// Stream of engine events from message processing.
  Stream<EngineEvent> get events => _eventController.stream;

  /// Dispose the processor.
  void dispose() {
    _eventController.close();
  }

  /// Process a server message.
  ///
  /// Returns the processing result and optionally emits events.
  Future<ProcessingResult> processMessage(ServerMessage message) async {
    try {
      return switch (message) {
        final WelcomeMessage msg => await _handleWelcome(msg),
        final SuccessMessage msg => await _handleSuccess(msg),
        final ErrorMessage msg => await _handleError(msg),
        final UsersMessage msg => await _handleUsers(msg),
        final OnlineUsersResponseMessage msg => await _handleOnlineUsers(msg),
        final UserStatusMessage msg => await _handleUserStatus(msg),
        final KeyBundleMessage msg => await _handleKeyBundle(msg),
        final IncomingMessage msg => await _handleIncomingMessage(msg),
        final MessageSentMessage msg => await _handleMessageSent(msg),
        final PendingMessagesDeliveredMessage msg =>
          await _handlePendingDelivered(msg),
        final UnknownServerMessage _ => ProcessingSuccess(),
        _ => ProcessingSuccess(), // Forward compatibility
      };
    } catch (e) {
      return ProcessingFailure('Failed to process message', e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Message Handlers
  // ─────────────────────────────────────────────────────────────────────────

  Future<ProcessingResult> _handleWelcome(WelcomeMessage message) async =>
      ProcessingSuccess();

  Future<ProcessingResult> _handleSuccess(SuccessMessage message) async =>
      ProcessingSuccess();

  Future<ProcessingResult> _handleError(ErrorMessage message) async {
    final event = EngineError(message.message);
    _eventController.add(event);
    return ProcessingSuccess(event: event);
  }

  Future<ProcessingResult> _handleUsers(UsersMessage message) async {
    final event = UsersListReceived(message.users);
    _eventController.add(event);
    return ProcessingSuccess(event: event);
  }

  Future<ProcessingResult> _handleOnlineUsers(
      OnlineUsersResponseMessage message,) async {
    print('[MessageProcessor] Handling online_users: ${message.users}');
    final event = UsersListReceived(message.users);
    _eventController.add(event);
    return ProcessingSuccess(event: event);
  }

  Future<ProcessingResult> _handleUserStatus(UserStatusMessage message) async {
    final event = UserStatusChanged(message.username, message.isOnline);
    _eventController.add(event);
    return ProcessingSuccess(event: event);
  }

  Future<ProcessingResult> _handleKeyBundle(KeyBundleMessage message) async =>
      ProcessingPending('key_bundle_for_${message.username}');

  Future<ProcessingResult> _handleMessageSent(
    MessageSentMessage message,
  ) async {
    final event = MessageSent(
      messageId: message.messageId,
      toUser: message.toUser,
      timestamp: message.dateTime,
    );
    _eventController.add(event);
    return ProcessingSuccess(event: event);
  }

  Future<ProcessingResult> _handlePendingDelivered(
    PendingMessagesDeliveredMessage message,
  ) async =>
      ProcessingSuccess();

  Future<ProcessingResult> _handleIncomingMessage(
    IncomingMessage message,
  ) async {
    print('[MessageProcessor] Handling incoming message: type=${message.messageType}, from=${message.fromUser}, isX3dh=${message.isX3dh}');
    return message.isX3dh
        ? _handleX3dhMessage(message)
        : _handleRatchetMessage(message);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // X3DH Message Handling
  // ─────────────────────────────────────────────────────────────────────────

  Future<ProcessingResult> _handleX3dhMessage(IncomingMessage message) async {
    final x3dh = message.asX3dh();
    if (x3dh == null) {
      return ProcessingFailure('Failed to parse X3DH message');
    }

    try {
      // Load our full key bundle with private keys
      final keyBundle = await _keyRepository.loadOwnKeyBundle();
      if (keyBundle == null) {
        return ProcessingFailure('No key bundle available');
      }

      // Build the X3DH message blob from the incoming message
      // The server sends a simplified format, we need to reconstruct the blob
      final messageBlob = _buildX3dhMessageBlob(x3dh, message.rawData);

      // Perform X3DH as receiver (Bob's perspective)
      final x3dhResult = await _x3dhEngine.receiverDecrypt(
        receiverKeys: keyBundle,
        messageBlob: messageBlob,
        findOtpkPrivate: (keyId) {
          final otpk = keyBundle.oneTimePrekeys[keyId];
          return otpk?.privateKey;
        },
      );

      // Consume the one-time prekey if used
      if (x3dh.usedOneTimePrekeyId != null) {
        await _keyRepository.consumeOneTimePrekey(x3dh.usedOneTimePrekeyId!);
      }

      // Create session from X3DH result using signed prekey as our initial DH
      // The tuple format is (publicKey, privateKey)
      await _sessionManager.createSessionAsResponder(
        peerUsername: x3dh.fromUser,
        sharedSecret: x3dhResult.sessionKey,
        ourDhKeyPair: (
          keyBundle.signedPrekey.publicKey,
          keyBundle.signedPrekey.privateKey,
        ),
        theirDhPublic: x3dhResult.senderEphemeralPublic,
      );

      // Emit message received event (plaintext was decrypted by X3DH)
      final event = MessageReceived(
        fromUser: x3dh.fromUser,
        plaintext: utf8.decode(x3dhResult.plaintext),
        timestamp: DateTime.now(),
      );
      _eventController.add(event);

      return ProcessingSuccess(event: event);
    } catch (e) {
      return ProcessingFailure('Failed to process X3DH message', e);
    }
  }

  /// Builds an X3dhMessageBlob from incoming message data.
  ///
  /// The server forwards the X3DH message with these fields:
  /// - metadata: base64-encoded JSON metadata (contains all key info)
  /// - signature: base64-encoded Ed25519 signature over metadata
  /// - ciphertext: base64-encoded encrypted message
  /// - nonce: base64-encoded encryption nonce
  X3dhMessageBlob _buildX3dhMessageBlob(
    IncomingX3dhMessage x3dh,
    Map<String, dynamic> rawData,
  ) {
    // The server forwards the metadata as base64-encoded JSON
    final metadataB64 = rawData['metadata'] as String?;
    
    X3dhMetadata metadata;
    if (metadataB64 != null && metadataB64.isNotEmpty) {
      // Decode the metadata: base64 -> UTF8 bytes -> JSON string -> Map
      final metadataBytes = base64Decode(metadataB64);
      final metadataJson = utf8.decode(metadataBytes);
      final metadataMap = jsonDecode(metadataJson) as Map<String, dynamic>;
      metadata = X3dhMetadata.fromMap(metadataMap);
    } else {
      // Fallback: try to construct metadata from individual fields (legacy)
      metadata = X3dhMetadata(
        version: rawData['version'] as int? ?? 1,
        type: 'X3DH_INIT',
        senderId: _parseBase64OrDefault(rawData['sender_id']),
        senderIdentityDhPublic: x3dh.identityKeyBytes,
        senderIdentitySignPublic:
            _parseBase64OrDefault(rawData['sender_identity_sign_public']),
        recipientId: _parseBase64OrDefault(rawData['recipient_id']),
        ephemeralPublic: x3dh.ephemeralKeyBytes,
        otpkId: x3dh.usedOneTimePrekeyId != null
            ? _intToBytes(x3dh.usedOneTimePrekeyId!)
            : null,
        messageId: _parseBase64OrDefault(rawData['message_id']),
        timestamp: rawData['timestamp'] as int? ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    }

    return X3dhMessageBlob(
      metadata: metadata,
      signature: _parseBase64OrDefault(rawData['signature']),
      ciphertext: x3dh.ciphertextBytes,
      nonce: _parseBase64OrDefault(rawData['nonce']),
    );
  }

  Uint8List _parseBase64OrDefault(dynamic value) {
    if (value == null) return Uint8List(0);
    if (value is String && value.isNotEmpty) {
      try {
        return base64Decode(value);
      } catch (_) {
        return Uint8List(0);
      }
    }
    return Uint8List(0);
  }

  Uint8List _intToBytes(int value) {
    final data = ByteData(4)..setInt32(0, value);
    return data.buffer.asUint8List();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ratchet Message Handling
  // ─────────────────────────────────────────────────────────────────────────

  Future<ProcessingResult> _handleRatchetMessage(
    IncomingMessage message,
  ) async {
    print('[MessageProcessor] _handleRatchetMessage: from=${message.fromUser}');
    final ratchet = message.asRatchet();
    if (ratchet == null) {
      print('[MessageProcessor] Failed to parse ratchet message');
      return ProcessingFailure('Failed to parse ratchet message');
    }
    
    print('[MessageProcessor] Parsed ratchet: from=${ratchet.fromUser}, dh_public=${ratchet.dhPublic.substring(0, 20)}..., dh_step=${ratchet.dhStep}, prev_chain=${ratchet.previousChainLength}, msg_num=${ratchet.messageNumber}');

    try {
      // Check if we have a session for this peer
      if (!_sessionManager.hasSession(ratchet.fromUser)) {
        print('[MessageProcessor] No session for ${ratchet.fromUser}');
        return ProcessingFailure(
          'No session for ${ratchet.fromUser}',
        );
      }
      
      print('[MessageProcessor] Found session for ${ratchet.fromUser}');

      // Parse the ratchet message
      final ratchetMessage = RatchetMessage(
        dhPublic: ratchet.dhPublicBytes,
        dhStep: ratchet.dhStep,
        prevChainLength: ratchet.previousChainLength,
        messageNumber: ratchet.messageNumber,
        ciphertext: ratchet.ciphertextBytes,
        nonce: ratchet.nonceBytes,
      );
      
      print('[MessageProcessor] RatchetMessage created, decrypting...');

      // Decrypt the message
      final plaintext = await _sessionManager.decryptMessage(
        peerUsername: ratchet.fromUser,
        message: ratchetMessage,
      );
      
      print('[MessageProcessor] Decrypted message: ${utf8.decode(plaintext)}');

      // Emit message received event
      final event = MessageReceived(
        fromUser: ratchet.fromUser,
        plaintext: utf8.decode(plaintext),
        timestamp: DateTime.now(),
      );
      _eventController.add(event);

      return ProcessingSuccess(event: event);
    } catch (e, stack) {
      print('[MessageProcessor] Failed to decrypt ratchet message: $e');
      print('[MessageProcessor] Stack: $stack');
      return ProcessingFailure('Failed to decrypt ratchet message', e);
    }
  }
}
