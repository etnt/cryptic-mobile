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
  /// Creates from a deserialized map.
  factory OneTimePrekey.fromMap(Map<String, dynamic> map) {
    return OneTimePrekey(
      keyId: map['key_id'] as int,
      publicKey: base64Decode(map['public_key'] as String),
      privateKey: base64Decode(map['private_key'] as String),
    );
  }

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
  Map<String, dynamic> toMap() => {
        'key_id': keyId,
        'public_key': base64Encode(publicKey),
        'private_key': base64Encode(privateKey),
      };

  /// Extracts only public components for sharing.
  OneTimePrekeyPublic get publicPart => OneTimePrekeyPublic(
        keyId: keyId,
        publicKey: publicKey,
      );
}

/// Public component of a one-time prekey.
class OneTimePrekeyPublic {
  /// Creates from a server response map (legacy format with integer key_id).
  factory OneTimePrekeyPublic.fromMap(Map<String, dynamic> map) {
    return OneTimePrekeyPublic(
      keyId: map['key_id'] as int,
      publicKey: base64Decode(map['public_key'] as String),
    );
  }

  /// Creates from server key bundle response (key ID is base64 string).
  factory OneTimePrekeyPublic.fromServerBundle(
      String keyIdBase64, String publicKeyBase64) {
    final keyIdBytes = base64Decode(keyIdBase64);
    // Use first 4 bytes as integer key ID for compatibility, or 0 if shorter
    final keyIdInt = keyIdBytes.length >= 4
        ? (keyIdBytes[0] << 24) |
            (keyIdBytes[1] << 16) |
            (keyIdBytes[2] << 8) |
            keyIdBytes[3]
        : 0;
    return OneTimePrekeyPublic(
      keyId: keyIdInt,
      publicKey: base64Decode(publicKeyBase64),
      keyIdBytes: keyIdBytes,
    );
  }

  /// Creates a public one-time prekey.
  const OneTimePrekeyPublic({
    required this.keyId,
    required this.publicKey,
    this.keyIdBytes,
  });

  /// Unique identifier for this prekey (integer format for local use).
  final int keyId;

  /// X25519 public key (32 bytes).
  final Uint8List publicKey;

  /// Key ID as bytes (from server, base64-decoded).
  /// Used when the server provides key ID as base64 binary.
  final Uint8List? keyIdBytes;

  /// Converts to a map for server upload.
  Map<String, dynamic> toMap() => {
        'key_id': keyId,
        'public_key': base64Encode(publicKey),
      };
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
  List<Map<String, dynamic>> toUploadList() =>
      prekeys.map((pk) => pk.publicPart.toMap()).toList();
}
