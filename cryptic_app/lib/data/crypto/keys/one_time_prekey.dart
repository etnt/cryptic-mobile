// lib/data/crypto/keys/one_time_prekey.dart
//
// One-time prekeys for X3DH key agreement.
//

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/constants/crypto_constants.dart';
import '../../../core/errors/app_exceptions.dart';

/// A one-time prekey for X3DH key agreement.
///
/// One-time prekeys provide additional forward secrecy:
/// - Each one-time prekey is used exactly once
/// - Deleted immediately after use
/// - Server maintains a pool of unused one-time prekeys
///
/// If no one-time prekeys are available, X3DH proceeds without one,
/// using only the signed prekey (slightly reduced forward secrecy).
class OneTimePrekey {
  /// Creates a one-time prekey.
  const OneTimePrekey({
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
  });

  /// Unique identifier for this prekey.
  final int keyId;

  /// X25519 public key (32 bytes).
  final Uint8List publicKey;

  /// X25519 private key (32 bytes).
  final Uint8List privateKey;

  /// Validates key sizes.
  void validate() {
    if (publicKey.length != CryptoConstants.x25519KeySize) {
      throw const InvalidKeyException(
        'One-time prekey public key must be ${CryptoConstants.x25519KeySize} bytes',
      );
    }
    if (privateKey.length != CryptoConstants.x25519KeySize) {
      throw const InvalidKeyException(
        'One-time prekey private key must be ${CryptoConstants.x25519KeySize} bytes',
      );
    }
  }

  /// Converts to a map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'key_id': keyId,
      'public_key': base64Encode(publicKey),
      'private_key': base64Encode(privateKey),
    };
  }

  /// Creates from a deserialized map.
  factory OneTimePrekey.fromMap(Map<String, dynamic> map) {
    return OneTimePrekey(
      keyId: map['key_id'] as int,
      publicKey: base64Decode(map['public_key'] as String),
      privateKey: base64Decode(map['private_key'] as String),
    );
  }

  /// Extracts only public components for sharing.
  OneTimePrekeyPublic get publicPart => OneTimePrekeyPublic(
        keyId: keyId,
        publicKey: publicKey,
      );
}

/// Public component of a one-time prekey.
class OneTimePrekeyPublic {
  /// Creates a public one-time prekey.
  const OneTimePrekeyPublic({
    required this.keyId,
    required this.publicKey,
  });

  /// Unique identifier for this prekey.
  final int keyId;

  /// X25519 public key (32 bytes).
  final Uint8List publicKey;

  /// Converts to a map for server upload.
  Map<String, dynamic> toMap() {
    return {
      'key_id': keyId,
      'public_key': base64Encode(publicKey),
    };
  }

  /// Creates from a server response map.
  factory OneTimePrekeyPublic.fromMap(Map<String, dynamic> map) {
    return OneTimePrekeyPublic(
      keyId: map['key_id'] as int,
      publicKey: base64Decode(map['public_key'] as String),
    );
  }
}

/// Batch of one-time prekeys for upload.
class OneTimePrekeyBatch {
  /// Creates a batch of one-time prekeys.
  const OneTimePrekeyBatch({
    required this.prekeys,
  });

  /// The prekeys in this batch.
  final List<OneTimePrekey> prekeys;

  /// Recommended number of one-time prekeys to maintain.
  static const int recommendedPoolSize = 100;

  /// Minimum number before triggering replenishment.
  static const int minimumPoolSize = 20;

  /// Converts public parts to a list for server upload.
  List<Map<String, dynamic>> toUploadList() {
    return prekeys.map((pk) => pk.publicPart.toMap()).toList();
  }
}
