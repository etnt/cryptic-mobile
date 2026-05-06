// lib/data/crypto/ratchet/double_ratchet.dart
//
// Double Ratchet Algorithm Implementation
//
// Implements forward-secure messaging with the Double Ratchet algorithm.
// Features:
// - Forward secrecy: Past messages secure if current keys compromised
// - Break-in recovery: Security restored after compromise
// - Out-of-order message handling via skipped key cache
//

import 'dart:typed_data';

import '../../../core/errors/app_exceptions.dart';
import '../primitives/chacha20_poly1305_service.dart';
import '../primitives/kdf_service.dart';
import '../primitives/x25519_service.dart';
import 'ratchet_message.dart';
import 'ratchet_state.dart';

/// Double Ratchet Algorithm Engine.
///
/// Provides forward-secure encryption and decryption of messages using
/// the Double Ratchet algorithm. The algorithm combines:
///
/// 1. **Symmetric-key ratchet**: Advances chain keys for each message
/// 2. **DH ratchet**: Injects fresh entropy via DH key exchanges
///
/// This provides both forward secrecy (past messages protected) and
/// break-in recovery (future messages protected after compromise).
class DoubleRatchet {
  /// Creates a Double Ratchet engine.
  DoubleRatchet({
    X25519Service? x25519,
    ChaCha20Poly1305Service? chacha,
    KdfService? kdf,
  })  : _x25519 = x25519 ?? X25519Service(),
        _chacha = chacha ?? ChaCha20Poly1305Service(),
        _kdf = kdf ?? KdfService();

  final X25519Service _x25519;
  final ChaCha20Poly1305Service _chacha;
  final KdfService _kdf;

  /// Initializes ratchet state for the sender (Alice).
  ///
  /// Called after X3DH key agreement. The ephemeral keypair from X3DH
  /// becomes the initial DH ratchet keypair.
  ///
  /// [rootKey] - Shared secret from X3DH (32 bytes).
  /// [dhKeyPair] - Initial DH keypair (from X3DH ephemeral).
  Future<RatchetState> initSender({
    required Uint8List rootKey,
    required (Uint8List, Uint8List) dhKeyPair,
  }) async {
    print('[DoubleRatchet] initSender: rootKey(sessionKey)=${_bytesToHex(rootKey)}');
    // Derive initial sending chain from root key
    final sendChainKey = await _deriveChainKey(rootKey, 'init');
    print('[DoubleRatchet] initSender: sendChainKey(init)=${_bytesToHex(sendChainKey)}');

    // Derive initial receiving chain (for Bob's replies)
    final recvChainKey = await _deriveChainKey(rootKey, 'resp');
    print('[DoubleRatchet] initSender: recvChainKey(resp)=${_bytesToHex(recvChainKey)}');

    return RatchetState(
      rootKey: rootKey,
      sendChainKey: sendChainKey,
      sendMessageNumber: 0,
      recvChainKey: recvChainKey,
      recvMessageNumber: 0,
      prevRecvChainLength: 0,
      dhSelf: dhKeyPair,
      dhRatchetStep: 0,
      sendingChainActive: true,
      receivingChainActive: true, // Ready for Bob's replies
      createdAt: DateTime.now(),
    );
  }

  /// Initializes ratchet state for the receiver (Bob).
  ///
  /// Called after receiving X3DH initial message.
  ///
  /// [rootKey] - Shared secret derived from X3DH.
  /// [dhKeyPair] - Own DH keypair.
  Future<RatchetState> initReceiver({
    required Uint8List rootKey,
    required (Uint8List, Uint8List) dhKeyPair,
  }) async {
    // Derive receiving chain to match Alice's sending chain
    final recvChainKey = await _deriveChainKey(rootKey, 'init');

    return RatchetState(
      rootKey: rootKey,
      sendChainKey: Uint8List(32), // Will be set on first send
      sendMessageNumber: 0,
      recvChainKey: recvChainKey,
      recvMessageNumber: 0,
      prevRecvChainLength: 0,
      dhSelf: dhKeyPair,
      dhRatchetStep: 0,
      sendingChainActive: false, // Activated on first send
      receivingChainActive: true,
      createdAt: DateTime.now(),
    );
  }

  /// Encrypts a message using the Double Ratchet.
  ///
  /// [plaintext] - Message to encrypt.
  /// [state] - Current ratchet state.
  ///
  /// Returns (message, newState) with encrypted message and updated state.
  Future<(RatchetMessage, RatchetState)> encryptMessage({
    required Uint8List plaintext,
    required RatchetState state,
  }) async {
    var currentState = state;

    // Activate sending chain if needed (receiver's first message)
    if (!currentState.sendingChainActive) {
      currentState = await _activateSendingChain(currentState);
    }

    // Check if DH ratchet needed (direction change)
    if (_shouldPerformDhRatchetOnSend(currentState)) {
      currentState = await _performDhRatchetOnSend(currentState);
    }

    // Derive message key from sending chain
    final (newChainKey, messageKey) = await _advanceSendingChain(
      currentState.sendChainKey,
      currentState.sendMessageNumber,
    );

    // Derive encryption key from message key
    final encKey = await _deriveEncryptionKey(messageKey);

    print('[DR-DEBUG] encryptMessage: msgNum=${currentState.sendMessageNumber}');
    print('[DR-DEBUG] sendChainKey=${_bytesToHex(currentState.sendChainKey)}');
    print('[DR-DEBUG] messageKey=${_bytesToHex(messageKey)}');
    print('[DR-DEBUG] encKey=${_bytesToHex(encKey)}');

    // Encrypt with ChaCha20-Poly1305
    final encrypted = await _chacha.encrypt(
      plaintext: plaintext,
      key: encKey,
    );

    print('[DR-DEBUG] nonce(${encrypted.nonce.length} bytes)=${_bytesToHex(encrypted.nonce)}');
    print('[DR-DEBUG] ciphertextWithTag(${encrypted.ciphertextWithTag.length} bytes)=${_bytesToHex(encrypted.ciphertextWithTag)}');

    // Build message (ciphertext includes tag appended)
    final message = RatchetMessage(
      dhPublic: currentState.dhSelf.$1,
      dhStep: currentState.dhRatchetStep,
      prevChainLength: currentState.prevRecvChainLength,
      messageNumber: currentState.sendMessageNumber,
      ciphertext: encrypted.ciphertextWithTag,
      nonce: encrypted.nonce,
    );

    // Update state
    final newState = currentState.copyWith(
      sendChainKey: newChainKey,
      sendMessageNumber: currentState.sendMessageNumber + 1,
      sendingChainActive: true,
      lastUpdated: DateTime.now(),
    );

    return (message, newState);
  }

  /// Decrypts a message using the Double Ratchet.
  ///
  /// [message] - Encrypted message to decrypt.
  /// [state] - Current ratchet state.
  ///
  /// Returns (plaintext, newState) with decrypted message and updated state.
  Future<(Uint8List, RatchetState)> decryptMessage({
    required RatchetMessage message,
    required RatchetState state,
  }) async {
    print('[DoubleRatchet] decryptMessage: msg.dhStep=${message.dhStep}, msg.msgNum=${message.messageNumber}');
    print('[DoubleRatchet] decryptMessage: state.dhRatchetStep=${state.dhRatchetStep}, state.recvMsgNum=${state.recvMessageNumber}');
    
    // Check if DH ratchet step needed
    final dhRatchetNeeded = _needsDhRatchet(message, state);
    print('[DoubleRatchet] decryptMessage: dhRatchetNeeded=$dhRatchetNeeded');

    var currentState = state;

    if (dhRatchetNeeded) {
      currentState = await _performDhRatchetOnReceive(message, currentState);
    } else if (currentState.dhRemote == null) {
      // First message - just store remote DH key
      currentState = currentState.copyWith(
        dhRemote: message.dhPublic,
      );
    }

    // Handle message gaps (out-of-order messages)
    currentState = await _handleMessageGap(
      currentState,
      message.messageNumber,
      message.dhStep,
    );

    // Try to decrypt from skipped keys first
    final skippedKeyId = SkippedKeyId(message.dhStep, message.messageNumber);
    if (currentState.skippedKeys.containsKey(skippedKeyId)) {
      final skippedEntry = currentState.skippedKeys[skippedKeyId]!;
      final encKey = await _deriveEncryptionKey(skippedEntry.messageKey);

      final plaintext = await _chacha.decrypt(
        ciphertext: message.ciphertext,
        key: encKey,
        nonce: message.nonce,
      );

      // Remove used skipped key
      currentState.skippedKeys.remove(skippedKeyId);

      return (plaintext, currentState.copyWith(lastUpdated: DateTime.now()));
    }

    // Derive message key from receiving chain
    print('[DoubleRatchet] decryptMessage: recvChainKey=${_bytesToHex(currentState.recvChainKey.sublist(0, 8))}...');
    print('[DoubleRatchet] decryptMessage: recvMessageNumber=${currentState.recvMessageNumber}');
    
    final (newChainKey, messageKey) = await _advanceReceivingChain(
      currentState.recvChainKey,
      currentState.recvMessageNumber,
    );
    print('[DoubleRatchet] decryptMessage: messageKey=${_bytesToHex(messageKey.sublist(0, 8))}...');

    // Derive encryption key
    final encKey = await _deriveEncryptionKey(messageKey);
    print('[DoubleRatchet] decryptMessage: encKey=${_bytesToHex(encKey.sublist(0, 8))}...');

    // Decrypt message
    final plaintext = await _chacha.decrypt(
      ciphertext: message.ciphertext,
      key: encKey,
      nonce: message.nonce,
    );

    // Update state
    final newState = currentState.copyWith(
      recvChainKey: newChainKey,
      recvMessageNumber: currentState.recvMessageNumber + 1,
      lastUpdated: DateTime.now(),
    );

    return (plaintext, newState);
  }

  /// Cleans up expired skipped keys.
  RatchetState cleanupExpiredKeys(RatchetState state) {
    final now = DateTime.now();
    final keysToRemove = <SkippedKeyId>[];

    for (final entry in state.skippedKeys.entries) {
      if (now.difference(entry.value.timestamp) > state.maxCacheAge) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      state.skippedKeys.remove(key);
    }

    return state.copyWith(lastUpdated: now);
  }

  // ==================== Private Methods ====================

  /// Derives a chain key from root key with context.
  /// 
  /// Uses Blake2b-based KDF to match Erlang server's kdf_derive_chain_key.
  Future<Uint8List> _deriveChainKey(Uint8List rootKey, String context) async {
    // kdf_derive(32, 0, Context, RootKey) in Erlang
    return _kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: context,
      masterKey: rootKey,
    );
  }

  /// Advances sending chain and derives message key.
  /// 
  /// Uses Blake2b-based KDF to match Erlang server's advance_sending_chain.
  Future<(Uint8List, Uint8List)> _advanceSendingChain(
    Uint8List chainKey,
    int messageNumber,
  ) async {
    // Match Erlang: MessageKey = kdf_derive(32, MsgNumber, "msg", ChainKey)
    //              NewChainKey = kdf_derive(32, MsgNumber + 1, "chain", ChainKey)
    return _kdf.deriveMessageKey(
      chainKey: chainKey,
      messageNumber: messageNumber,
    );
  }

  /// Advances receiving chain and derives message key.
  /// 
  /// Uses Blake2b-based KDF to match Erlang server's advance_receiving_chain.
  Future<(Uint8List, Uint8List)> _advanceReceivingChain(
    Uint8List chainKey,
    int messageNumber,
  ) async => _kdf.deriveMessageKey(
      chainKey: chainKey,
      messageNumber: messageNumber,
    );

  /// Derives encryption key from message key.
  /// 
  /// Uses Blake2b-based KDF to match Erlang server's kdf_mk.
  Future<Uint8List> _deriveEncryptionKey(Uint8List messageKey) async {
    // Match Erlang: EncKey = kdf_derive(32, 0, "enc", MessageKey)
    return _kdf.deriveEncryptionKey(messageKey: messageKey);
  }

  /// Checks if DH ratchet is needed on receive.
  bool _needsDhRatchet(RatchetMessage message, RatchetState state) {
    if (state.dhRemote == null) {
      return message.dhStep > state.dhRatchetStep;
    }
    return !_bytesEqual(message.dhPublic, state.dhRemote!);
  }

  /// Checks if DH ratchet should be performed on send.
  bool _shouldPerformDhRatchetOnSend(RatchetState state) {
    // DH ratchet on send after receiving messages (direction change)
    return state.dhRemote != null &&
        state.recvMessageNumber > 0 &&
        state.sendMessageNumber == 0;
  }

  /// Activates the sending chain for a receiver.
  Future<RatchetState> _activateSendingChain(RatchetState state) async {
    if (state.sendingChainActive) {
      return state;
    }

    if (state.dhRemote == null) {
      throw const CryptoException('Cannot activate sending chain: no remote DH key');
    }

    // Derive sending chain from root key
    final sendChainKey = await _deriveChainKey(state.rootKey, 'resp');

    return state.copyWith(
      sendChainKey: sendChainKey,
      sendMessageNumber: 0,
      sendingChainActive: true,
    );
  }

  /// Performs DH ratchet step on receive.
  Future<RatchetState> _performDhRatchetOnReceive(
    RatchetMessage message,
    RatchetState state,
  ) async {
    print('[DoubleRatchet] _performDhRatchetOnReceive: message.dhStep=${message.dhStep}, state.dhRatchetStep=${state.dhRatchetStep}');
    print('[DoubleRatchet] _performDhRatchetOnReceive: our dhSelf pubkey=${_bytesToHex(state.dhSelf.$1.sublist(0, 8))}...');
    print('[DoubleRatchet] _performDhRatchetOnReceive: their dhPublic=${_bytesToHex(message.dhPublic.sublist(0, 8))}...');
    
    // Store previous chain length
    final prevLength = state.recvMessageNumber;

    // Compute shared secret with sender's new DH key using OUR CURRENT private key
    final dhOutput = await _x25519.computeSharedSecret(
      privateKey: state.dhSelf.$2,
      publicKey: message.dhPublic,
    );
    print('[DoubleRatchet] _performDhRatchetOnReceive: dhOutput=${_bytesToHex(dhOutput.sublist(0, 8))}...');

    // Generate new DH keypair for our next send
    final newDhKeyPair = await _x25519.generateKeyPair();

    // Derive new root key and chain keys
    // Per Erlang: On receive, use InitChainKey for FUTURE sending, RespChainKey for RECEIVING
    final (newRootKey, initChainKey, respChainKey) = await _kdf.deriveRatchetKeys(
      rootKey: state.rootKey,
      dhOutput: dhOutput,
    );
    print('[DoubleRatchet] _performDhRatchetOnReceive: newRootKey=${_bytesToHex(newRootKey.sublist(0, 8))}...');
    print('[DoubleRatchet] _performDhRatchetOnReceive: initChainKey (for future send)=${_bytesToHex(initChainKey.sublist(0, 8))}...');
    print('[DoubleRatchet] _performDhRatchetOnReceive: respChainKey (for recv)=${_bytesToHex(respChainKey.sublist(0, 8))}...');

    return state.copyWith(
      rootKey: newRootKey,
      sendChainKey: initChainKey,  // For FUTURE sending
      sendMessageNumber: 0,
      recvChainKey: respChainKey,  // For current RECEIVING
      recvMessageNumber: 0,
      prevRecvChainLength: prevLength,
      dhSelf: (newDhKeyPair.publicKey, newDhKeyPair.privateKey),
      dhRemote: message.dhPublic,
      dhRatchetStep: state.dhRatchetStep + 1,
      sendingChainActive: true,
      receivingChainActive: true,
    );
  }
  
  String _bytesToHex(Uint8List bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Performs DH ratchet step on send.
  Future<RatchetState> _performDhRatchetOnSend(RatchetState state) async {
    // Generate new DH keypair
    final newDhKeyPair = await _x25519.generateKeyPair();

    // Compute shared secret using our NEW private key and their current public key
    final dhOutput = await _x25519.computeSharedSecret(
      privateKey: newDhKeyPair.privateKey,
      publicKey: state.dhRemote!,
    );

    // Derive new root key and chain keys
    // Per Erlang: On send after receiving, use RespChainKey for sending
    // (Bob uses responder chain for sending, Alice will derive same for receiving)
    final (newRootKey, _, respChainKey) = await _kdf.deriveRatchetKeys(
      rootKey: state.rootKey,
      dhOutput: dhOutput,
    );

    return state.copyWith(
      rootKey: newRootKey,
      sendChainKey: respChainKey,
      sendMessageNumber: 0,
      dhSelf: (newDhKeyPair.publicKey, newDhKeyPair.privateKey),
      dhRatchetStep: state.dhRatchetStep + 1,
    );
  }

  /// Handles message gaps by pre-deriving skipped keys.
  Future<RatchetState> _handleMessageGap(
    RatchetState state,
    int incomingMsgNum,
    int incomingDhStep,
  ) async {
    // No gap if message is in order
    if (incomingMsgNum <= state.recvMessageNumber) {
      return state;
    }

    // Check gap isn't too large
    final gap = incomingMsgNum - state.recvMessageNumber;
    if (gap > state.maxSkip) {
      throw CryptoException('Message gap too large: $gap > ${state.maxSkip}');
    }

    // Pre-derive and cache skipped keys
    var chainKey = state.recvChainKey;
    for (var i = state.recvMessageNumber; i < incomingMsgNum; i++) {
      final (newChainKey, messageKey) = await _advanceReceivingChain(chainKey, i);

      final keyId = SkippedKeyId(incomingDhStep, i);
      state.skippedKeys[keyId] = SkippedKeyEntry(
        messageKey: messageKey,
        timestamp: DateTime.now(),
        dhPublic: state.dhRemote ?? Uint8List(32),
      );

      chainKey = newChainKey;

      // Enforce cache size limit
      if (state.skippedKeys.length > state.maxCacheSize) {
        _removeOldestSkippedKey(state);
      }
    }

    return state.copyWith(recvChainKey: chainKey);
  }

  /// Removes the oldest skipped key.
  void _removeOldestSkippedKey(RatchetState state) {
    if (state.skippedKeys.isEmpty) return;

    SkippedKeyId? oldestKey;
    DateTime? oldestTime;

    for (final entry in state.skippedKeys.entries) {
      if (oldestTime == null || entry.value.timestamp.isBefore(oldestTime)) {
        oldestKey = entry.key;
        oldestTime = entry.value.timestamp;
      }
    }

    if (oldestKey != null) {
      state.skippedKeys.remove(oldestKey);
    }
  }

  /// Constant-time byte comparison.
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
