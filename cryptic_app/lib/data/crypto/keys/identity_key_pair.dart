// lib/data/crypto/keys/identity_key_pair.dart
//
// Identity key pairs for X3DH and message signing.
//

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/constants/crypto_constants.dart';
import '../../../core/errors/app_exceptions.dart';

/// Represents the user's long-term identity key pair.
///
/// Identity keys in Cryptic consist of:
/// - Ed25519 key pair for signing (identity verification)
/// - X25519 key pair for DH key agreement (encryption)
///
/// The Ed25519 public key is the canonical "identity" and is signed
/// to prove ownership of the X25519 DH key.
class IdentityKeyPair {

  /// Creates from a deserialized map.
  factory IdentityKeyPair.fromMap(Map<String, dynamic> map) {
    return IdentityKeyPair(
      signPublicKey: base64Decode(map['sign_public_key'] as String),
      signPrivateKey: base64Decode(map['sign_private_key'] as String),
      dhPublicKey: base64Decode(map['dh_public_key'] as String),
      dhPrivateKey: base64Decode(map['dh_private_key'] as String),
    );
  }
  /// Creates an identity key pair.
  const IdentityKeyPair({
    required this.signPublicKey,
    required this.signPrivateKey,
    required this.dhPublicKey,
    required this.dhPrivateKey,
  });

  /// Ed25519 public key for signing (32 bytes).
  final Uint8List signPublicKey;

  /// Ed25519 private key for signing (64 bytes).
  final Uint8List signPrivateKey;

  /// X25519 public key for DH (32 bytes).
  final Uint8List dhPublicKey;

  /// X25519 private key for DH (32 bytes).
  final Uint8List dhPrivateKey;

  /// Validates key sizes match expected constants.
  void validate() {
    if (signPublicKey.length != CryptoConstants.ed25519PublicKeySize) {
      throw const InvalidKeyException(
        'Ed25519 public key must be ${CryptoConstants.ed25519PublicKeySize} bytes',
      );
    }
    if (signPrivateKey.length != CryptoConstants.ed25519PrivateKeySize) {
      throw const InvalidKeyException(
        'Ed25519 private key must be ${CryptoConstants.ed25519PrivateKeySize} bytes',
      );
    }
    if (dhPublicKey.length != CryptoConstants.x25519KeySize) {
      throw const InvalidKeyException(
        'X25519 public key must be ${CryptoConstants.x25519KeySize} bytes',
      );
    }
    if (dhPrivateKey.length != CryptoConstants.x25519KeySize) {
      throw const InvalidKeyException(
        'X25519 private key must be ${CryptoConstants.x25519KeySize} bytes',
      );
    }
  }

  /// Converts to a map for serialization.
  Map<String, String> toMap() => {
      'sign_public_key': base64Encode(signPublicKey),
      'sign_private_key': base64Encode(signPrivateKey),
      'dh_public_key': base64Encode(dhPublicKey),
      'dh_private_key': base64Encode(dhPrivateKey),
    };

  /// Extracts only public keys for sharing.
  IdentityPublicKeys get publicKeys => IdentityPublicKeys(
        signPublicKey: signPublicKey,
        dhPublicKey: dhPublicKey,
      );
}

/// Public identity keys for sharing with other users.
class IdentityPublicKeys {

  /// Creates from a deserialized map.
  factory IdentityPublicKeys.fromMap(Map<String, dynamic> map) {
    return IdentityPublicKeys(
      signPublicKey: base64Decode(map['identity_sign_public'] as String),
      dhPublicKey: base64Decode(map['identity_dh_public'] as String),
    );
  }
  /// Creates identity public keys.
  const IdentityPublicKeys({
    required this.signPublicKey,
    required this.dhPublicKey,
  });

  /// Ed25519 public key for signature verification.
  final Uint8List signPublicKey;

  /// X25519 public key for DH key agreement.
  final Uint8List dhPublicKey;

  /// Converts to a map for serialization.
  Map<String, String> toMap() => {
      'identity_sign_public': base64Encode(signPublicKey),
      'identity_dh_public': base64Encode(dhPublicKey),
    };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! IdentityPublicKeys) return false;
    return _bytesEqual(signPublicKey, other.signPublicKey) &&
        _bytesEqual(dhPublicKey, other.dhPublicKey);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(signPublicKey),
        Object.hashAll(dhPublicKey),
      );

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
