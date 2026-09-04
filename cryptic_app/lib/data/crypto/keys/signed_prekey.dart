// lib/data/crypto/keys/signed_prekey.dart
//
// Signed prekey for X3DH key agreement.
//

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/constants/crypto_constants.dart';
import '../../../core/errors/app_exceptions.dart';

/// A signed prekey used in X3DH key agreement.
///
/// The signed prekey is:
/// - An X25519 key pair
/// - Signed by the user's Ed25519 identity key
/// - Rotated periodically (typically weekly)
///
/// The signature proves ownership of the prekey, preventing
/// man-in-the-middle attacks on initial key agreement.
class SignedPrekey {
  /// Creates from a deserialized map.
  factory SignedPrekey.fromMap(Map<String, dynamic> map) {
    return SignedPrekey(
      keyId: map['key_id'] as int,
      publicKey: base64Decode(map['public_key'] as String),
      privateKey: base64Decode(map['private_key'] as String),
      signature: base64Decode(map['signature'] as String),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  /// Creates a signed prekey.
  const SignedPrekey({
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
    required this.signature,
    required this.timestamp,
  });

  /// Unique identifier for this prekey.
  final int keyId;

  /// X25519 public key (32 bytes).
  final Uint8List publicKey;

  /// X25519 private key (32 bytes).
  final Uint8List privateKey;

  /// Ed25519 signature over the public key (64 bytes).
  final Uint8List signature;

  /// When this prekey was generated (for rotation tracking).
  final DateTime timestamp;

  /// Validates key and signature sizes.
  void validate() {
    if (publicKey.length != CryptoConstants.x25519KeySize) {
      throw const InvalidKeyException(
        'Signed prekey public key must be ${CryptoConstants.x25519KeySize} bytes',
      );
    }
    if (privateKey.length != CryptoConstants.x25519KeySize) {
      throw const InvalidKeyException(
        'Signed prekey private key must be ${CryptoConstants.x25519KeySize} bytes',
      );
    }
    if (signature.length != CryptoConstants.ed25519SignatureSize) {
      throw const InvalidKeyException(
        'Signed prekey signature must be ${CryptoConstants.ed25519SignatureSize} bytes',
      );
    }
  }

  /// Whether this prekey should be rotated.
  ///
  /// Prekeys are typically rotated after 7 days.
  bool shouldRotate({Duration maxAge = const Duration(days: 7)}) =>
      DateTime.now().difference(timestamp) > maxAge;

  /// Converts to a map for serialization.
  Map<String, dynamic> toMap() => {
        'key_id': keyId,
        'public_key': base64Encode(publicKey),
        'private_key': base64Encode(privateKey),
        'signature': base64Encode(signature),
        'timestamp': timestamp.toIso8601String(),
      };

  /// Extracts only public components for sharing.
  SignedPrekeyPublic get publicPart => SignedPrekeyPublic(
        keyId: keyId,
        publicKey: publicKey,
        signature: signature,
      );
}

/// Public components of a signed prekey.
class SignedPrekeyPublic {
  /// Creates from a server response map.
  factory SignedPrekeyPublic.fromMap(Map<String, dynamic> map) {
    return SignedPrekeyPublic(
      keyId: map['key_id'] as int,
      publicKey: base64Decode(map['public_key'] as String),
      signature: base64Decode(map['signature'] as String),
    );
  }

  /// Creates a public signed prekey.
  const SignedPrekeyPublic({
    required this.keyId,
    required this.publicKey,
    required this.signature,
  });

  /// Unique identifier for this prekey.
  final int keyId;

  /// X25519 public key (32 bytes).
  final Uint8List publicKey;

  /// Ed25519 signature over the public key (64 bytes).
  final Uint8List signature;

  /// Converts to a map for server upload.
  Map<String, dynamic> toMap() => {
        'key_id': keyId,
        'public_key': base64Encode(publicKey),
        'signature': base64Encode(signature),
      };
}
