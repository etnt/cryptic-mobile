// lib/data/crypto/ratchet/ratchet_message.dart
//
// Double Ratchet Message Structure
//

import 'dart:convert';
import 'dart:typed_data';

/// A Double Ratchet encrypted message.
///
/// Contains all the information needed to decrypt a message:
/// - DH ratchet public key
/// - Chain/message counters
/// - Encrypted payload
class RatchetMessage {
  /// Creates from a map (e.g., from JSON/WebSocket).
  factory RatchetMessage.fromMap(Map<String, dynamic> map) {
    return RatchetMessage(
      dhPublic: base64Decode(map['dh_public'] as String),
      dhStep: map['dh_step'] as int,
      prevChainLength: map['prev_chain_length'] as int,
      messageNumber: map['msg_number'] as int,
      ciphertext: base64Decode(map['ciphertext'] as String),
      nonce: base64Decode(map['nonce'] as String),
    );
  }

  /// Creates a ratchet message.
  const RatchetMessage({
    required this.dhPublic,
    required this.dhStep,
    required this.prevChainLength,
    required this.messageNumber,
    required this.ciphertext,
    required this.nonce,
  });

  /// Sender's current DH public key.
  final Uint8List dhPublic;

  /// Sender's current DH ratchet step.
  final int dhStep;

  /// Length of sender's previous receiving chain.
  final int prevChainLength;

  /// Message number in current sending chain.
  final int messageNumber;

  /// ChaCha20-Poly1305 encrypted message.
  final Uint8List ciphertext;

  /// Nonce used for encryption.
  final Uint8List nonce;

  /// Converts to a map for JSON serialization.
  Map<String, dynamic> toMap() => {
        'dh_public': base64Encode(dhPublic),
        'dh_step': dhStep,
        'prev_chain_length': prevChainLength,
        'msg_number': messageNumber,
        'ciphertext': base64Encode(ciphertext),
        'nonce': base64Encode(nonce),
      };
}
