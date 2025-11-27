// lib/data/crypto/ratchet/ratchet_state.dart
//
// Double Ratchet State Management
//
// Maintains all state needed for the Double Ratchet algorithm including
// chain keys, DH keys, and skipped message key cache.
//

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/constants/crypto_constants.dart';

/// A skipped message key entry for out-of-order message handling.
class SkippedKeyEntry {
  /// Creates a skipped key entry.
  const SkippedKeyEntry({
    required this.messageKey,
    required this.timestamp,
    required this.dhPublic,
  });

  /// The derived message key.
  final Uint8List messageKey;

  /// When this key was derived (for cleanup).
  final DateTime timestamp;

  /// DH public key active when derived.
  final Uint8List dhPublic;

  /// Converts to a map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'message_key': base64Encode(messageKey),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'dh_public': base64Encode(dhPublic),
    };
  }

  /// Creates from a map.
  factory SkippedKeyEntry.fromMap(Map<String, dynamic> map) {
    return SkippedKeyEntry(
      messageKey: base64Decode(map['message_key'] as String),
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      dhPublic: base64Decode(map['dh_public'] as String),
    );
  }
}

/// Key for the skipped keys map: (dhStep, messageNumber).
class SkippedKeyId {
  /// Creates a skipped key identifier.
  const SkippedKeyId(this.dhStep, this.messageNumber);

  /// The DH ratchet step when this key was derived.
  final int dhStep;

  /// The message number in the chain.
  final int messageNumber;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SkippedKeyId &&
        other.dhStep == dhStep &&
        other.messageNumber == messageNumber;
  }

  @override
  int get hashCode => Object.hash(dhStep, messageNumber);

  /// Converts to a string key for map serialization.
  String toKey() => '$dhStep:$messageNumber';

  /// Creates from a string key.
  factory SkippedKeyId.fromKey(String key) {
    final parts = key.split(':');
    return SkippedKeyId(int.parse(parts[0]), int.parse(parts[1]));
  }
}

/// Complete Double Ratchet state.
///
/// This contains all the cryptographic state needed for the Double Ratchet
/// algorithm, including:
/// - Root chain state
/// - Sending and receiving chain states
/// - DH ratchet keys
/// - Skipped message key cache
class RatchetState {
  /// Creates a ratchet state.
  RatchetState({
    required this.rootKey,
    required this.sendChainKey,
    required this.sendMessageNumber,
    required this.recvChainKey,
    required this.recvMessageNumber,
    required this.prevRecvChainLength,
    required this.dhSelf,
    this.dhRemote,
    required this.dhRatchetStep,
    Map<SkippedKeyId, SkippedKeyEntry>? skippedKeys,
    this.maxSkip = CryptoConstants.maxSkipPerStep,
    this.maxCacheSize = CryptoConstants.maxSkippedMessageKeys,
    this.maxCacheAge = const Duration(hours: 24),
    required this.sendingChainActive,
    required this.receivingChainActive,
    required this.createdAt,
    DateTime? lastUpdated,
  })  : skippedKeys = skippedKeys ?? {},
        lastUpdated = lastUpdated ?? DateTime.now();

  // Root chain state

  /// Current root key (32 bytes).
  Uint8List rootKey;

  // Sending chain state

  /// Current sending chain key (32 bytes).
  Uint8List sendChainKey;

  /// Message number in current sending chain.
  int sendMessageNumber;

  // Receiving chain state

  /// Current receiving chain key (32 bytes).
  Uint8List recvChainKey;

  /// Expected next message number in receiving chain.
  int recvMessageNumber;

  /// Messages in previous receiving chain (for gap handling).
  int prevRecvChainLength;

  // DH ratchet keys

  /// Own DH keypair (public, private).
  (Uint8List, Uint8List) dhSelf;

  /// Remote party's DH public key (null until first message received).
  Uint8List? dhRemote;

  /// Current DH ratchet step number.
  int dhRatchetStep;

  // Skipped message key store (for out-of-order delivery)

  /// Cache of skipped message keys.
  final Map<SkippedKeyId, SkippedKeyEntry> skippedKeys;

  // Configuration

  /// Maximum messages to skip in sequence.
  final int maxSkip;

  /// Maximum skipped keys to cache.
  final int maxCacheSize;

  /// Maximum age for cached keys.
  final Duration maxCacheAge;

  // Chain state tracking

  /// True if we can send messages.
  bool sendingChainActive;

  /// True if we can receive messages.
  bool receivingChainActive;

  // Metadata

  /// When this ratchet was initialized.
  final DateTime createdAt;

  /// When state was last updated.
  DateTime lastUpdated;

  /// Creates a copy with updated fields.
  RatchetState copyWith({
    Uint8List? rootKey,
    Uint8List? sendChainKey,
    int? sendMessageNumber,
    Uint8List? recvChainKey,
    int? recvMessageNumber,
    int? prevRecvChainLength,
    (Uint8List, Uint8List)? dhSelf,
    Uint8List? dhRemote,
    int? dhRatchetStep,
    bool? sendingChainActive,
    bool? receivingChainActive,
    DateTime? lastUpdated,
  }) {
    return RatchetState(
      rootKey: rootKey ?? this.rootKey,
      sendChainKey: sendChainKey ?? this.sendChainKey,
      sendMessageNumber: sendMessageNumber ?? this.sendMessageNumber,
      recvChainKey: recvChainKey ?? this.recvChainKey,
      recvMessageNumber: recvMessageNumber ?? this.recvMessageNumber,
      prevRecvChainLength: prevRecvChainLength ?? this.prevRecvChainLength,
      dhSelf: dhSelf ?? this.dhSelf,
      dhRemote: dhRemote ?? this.dhRemote,
      dhRatchetStep: dhRatchetStep ?? this.dhRatchetStep,
      skippedKeys: skippedKeys,
      maxSkip: maxSkip,
      maxCacheSize: maxCacheSize,
      maxCacheAge: maxCacheAge,
      sendingChainActive: sendingChainActive ?? this.sendingChainActive,
      receivingChainActive: receivingChainActive ?? this.receivingChainActive,
      createdAt: createdAt,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }

  /// Converts to a map for serialization.
  Map<String, dynamic> toMap() {
    final skippedKeysMap = <String, dynamic>{};
    for (final entry in skippedKeys.entries) {
      skippedKeysMap[entry.key.toKey()] = entry.value.toMap();
    }

    return {
      'root_key': base64Encode(rootKey),
      'send_chain_key': base64Encode(sendChainKey),
      'send_message_number': sendMessageNumber,
      'recv_chain_key': base64Encode(recvChainKey),
      'recv_message_number': recvMessageNumber,
      'prev_recv_chain_length': prevRecvChainLength,
      'dh_self_public': base64Encode(dhSelf.$1),
      'dh_self_private': base64Encode(dhSelf.$2),
      'dh_remote': dhRemote != null ? base64Encode(dhRemote!) : null,
      'dh_ratchet_step': dhRatchetStep,
      'skipped_keys': skippedKeysMap,
      'max_skip': maxSkip,
      'max_cache_size': maxCacheSize,
      'max_cache_age_ms': maxCacheAge.inMilliseconds,
      'sending_chain_active': sendingChainActive,
      'receiving_chain_active': receivingChainActive,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_updated': lastUpdated.millisecondsSinceEpoch,
    };
  }

  /// Creates from a map.
  factory RatchetState.fromMap(Map<String, dynamic> map) {
    final skippedKeysMap = map['skipped_keys'] as Map<String, dynamic>? ?? {};
    final skippedKeys = <SkippedKeyId, SkippedKeyEntry>{};
    for (final entry in skippedKeysMap.entries) {
      final id = SkippedKeyId.fromKey(entry.key);
      skippedKeys[id] =
          SkippedKeyEntry.fromMap(entry.value as Map<String, dynamic>);
    }

    return RatchetState(
      rootKey: base64Decode(map['root_key'] as String),
      sendChainKey: base64Decode(map['send_chain_key'] as String),
      sendMessageNumber: map['send_message_number'] as int,
      recvChainKey: base64Decode(map['recv_chain_key'] as String),
      recvMessageNumber: map['recv_message_number'] as int,
      prevRecvChainLength: map['prev_recv_chain_length'] as int,
      dhSelf: (
        base64Decode(map['dh_self_public'] as String),
        base64Decode(map['dh_self_private'] as String),
      ),
      dhRemote: map['dh_remote'] != null
          ? base64Decode(map['dh_remote'] as String)
          : null,
      dhRatchetStep: map['dh_ratchet_step'] as int,
      skippedKeys: skippedKeys,
      maxSkip: map['max_skip'] as int? ?? CryptoConstants.maxSkipPerStep,
      maxCacheSize:
          map['max_cache_size'] as int? ?? CryptoConstants.maxSkippedMessageKeys,
      maxCacheAge: Duration(
        milliseconds: map['max_cache_age_ms'] as int? ?? 86400000,
      ),
      sendingChainActive: map['sending_chain_active'] as bool,
      receivingChainActive: map['receiving_chain_active'] as bool,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastUpdated:
          DateTime.fromMillisecondsSinceEpoch(map['last_updated'] as int),
    );
  }

  /// Gets summary info (safe for logging).
  Map<String, dynamic> getInfo() {
    return {
      'dh_ratchet_step': dhRatchetStep,
      'send_message_number': sendMessageNumber,
      'recv_message_number': recvMessageNumber,
      'prev_recv_chain_length': prevRecvChainLength,
      'skipped_keys_count': skippedKeys.length,
      'sending_chain_active': sendingChainActive,
      'receiving_chain_active': receivingChainActive,
      'has_remote_dh': dhRemote != null,
      'created_at': createdAt.toIso8601String(),
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}
