// lib/data/crypto/primitives/x25519_service.dart
//
// X25519 Elliptic Curve Diffie-Hellman key agreement
//
// Used for:
// - X3DH key agreement (DH1, DH2, DH3, DH4)
// - Double Ratchet DH ratchet steps
//

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/constants/crypto_constants.dart';
import '../../../core/errors/app_exceptions.dart';

/// X25519 key pair for Diffie-Hellman key agreement.
class X25519KeyPair {
  /// Creates a new X25519 key pair.
  const X25519KeyPair({
    required this.publicKey,
    required this.privateKey,
  });

  /// The public key (32 bytes).
  final Uint8List publicKey;

  /// The private key (32 bytes).
  final Uint8List privateKey;

  /// Validates key sizes.
  bool get isValid =>
      publicKey.length == CryptoConstants.x25519KeySize &&
      privateKey.length == CryptoConstants.x25519KeySize;
}

/// Service for X25519 Elliptic Curve Diffie-Hellman operations.
///
/// Provides:
/// - Key pair generation
/// - Shared secret computation (ECDH)
///
/// This is the core primitive used in both X3DH and Double Ratchet
/// for establishing shared secrets between parties.
class X25519Service {
  /// Creates a new X25519 service instance.
  X25519Service() : _algorithm = X25519();

  final X25519 _algorithm;

  /// Generates a new X25519 key pair.
  ///
  /// Returns a key pair suitable for Diffie-Hellman operations.
  Future<X25519KeyPair> generateKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    return X25519KeyPair(
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: Uint8List.fromList(privateKeyBytes),
    );
  }

  /// Computes a shared secret using ECDH.
  ///
  /// [privateKey] - Our 32-byte X25519 private key.
  /// [publicKey] - Their 32-byte X25519 public key.
  ///
  /// Returns a 32-byte shared secret.
  ///
  /// Note: The shared secret should be passed through a KDF (like HKDF)
  /// before use as an encryption key.
  Future<Uint8List> sharedSecret({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) async {
    if (privateKey.length != CryptoConstants.x25519KeySize) {
      throw const InvalidKeyException(
        'X25519 private key must be 32 bytes',
      );
    }

    if (publicKey.length != CryptoConstants.x25519KeySize) {
      throw const InvalidKeyException(
        'X25519 public key must be 32 bytes',
      );
    }

    // Reconstruct key pair from private key bytes
    final keyPair = await _algorithm.newKeyPairFromSeed(privateKey);

    // Create their public key object
    final remotePublicKey = SimplePublicKey(
      publicKey,
      type: KeyPairType.x25519,
    );

    // Perform ECDH
    final sharedSecretKey = await _algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: remotePublicKey,
    );

    final secretBytes = await sharedSecretKey.extractBytes();
    return Uint8List.fromList(secretBytes);
  }

  /// Alias for [sharedSecret] for API compatibility.
  Future<Uint8List> computeSharedSecret({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) =>
      sharedSecret(privateKey: privateKey, publicKey: publicKey);

  /// Computes shared secret from a key pair object.
  ///
  /// Convenience method when you have an [X25519KeyPair].
  Future<Uint8List> sharedSecretFromKeyPair(
    X25519KeyPair ourKeyPair,
    Uint8List theirPublicKey,
  ) =>
      sharedSecret(privateKey: ourKeyPair.privateKey, publicKey: theirPublicKey);
}
