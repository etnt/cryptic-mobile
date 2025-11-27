// lib/data/crypto/primitives/ed25519_service.dart
//
// Ed25519 digital signature operations
//
// Used for:
// - Identity key signing (signed prekey signatures)
// - Message authentication where needed
//

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/constants/crypto_constants.dart';
import '../../../core/errors/app_exceptions.dart';

/// Ed25519 key pair for signing operations.
class Ed25519KeyPair {
  /// Creates a new Ed25519 key pair.
  const Ed25519KeyPair({
    required this.publicKey,
    required this.privateKey,
  });

  /// The public key (32 bytes).
  final Uint8List publicKey;

  /// The private key (64 bytes - includes public key suffix in libsodium format).
  final Uint8List privateKey;

  /// Validates key sizes.
  bool get isValid =>
      publicKey.length == CryptoConstants.ed25519PublicKeySize &&
      privateKey.length == CryptoConstants.ed25519PrivateKeySize;
}

/// Service for Ed25519 digital signature operations.
///
/// Provides:
/// - Key pair generation
/// - Message signing
/// - Signature verification
///
/// Compatible with the Erlang Cryptic server implementation.
class Ed25519Service {
  /// Creates a new Ed25519 service instance.
  Ed25519Service() : _algorithm = Ed25519();

  final Ed25519 _algorithm;

  /// Generates a new Ed25519 key pair.
  ///
  /// Returns a key pair suitable for signing operations.
  /// The private key is 64 bytes (seed + public key).
  Future<Ed25519KeyPair> generateKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    // Extract raw bytes
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKeyBytes = Uint8List.fromList(publicKey.bytes);

    // The cryptography package returns 32-byte seed, but Erlang expects 64 bytes
    // (seed || public_key). We need to construct the full private key.
    final fullPrivateKey = Uint8List(CryptoConstants.ed25519PrivateKeySize);
    fullPrivateKey.setRange(0, 32, privateKeyBytes);
    fullPrivateKey.setRange(32, 64, publicKeyBytes);

    return Ed25519KeyPair(
      publicKey: publicKeyBytes,
      privateKey: fullPrivateKey,
    );
  }

  /// Signs a message with the given private key.
  ///
  /// [message] - The message bytes to sign.
  /// [privateKey] - The 64-byte Ed25519 private key.
  ///
  /// Returns a 64-byte signature.
  Future<Uint8List> sign({
    required Uint8List message,
    required Uint8List privateKey,
  }) async {
    if (privateKey.length != CryptoConstants.ed25519PrivateKeySize) {
      throw const InvalidKeyException(
        'Ed25519 private key must be 64 bytes',
      );
    }

    // Extract the 32-byte seed from the full private key
    final seed = privateKey.sublist(0, 32);

    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final signature = await _algorithm.sign(message, keyPair: keyPair);

    return Uint8List.fromList(signature.bytes);
  }

  /// Verifies a signature against a message and public key.
  ///
  /// [message] - The original message bytes.
  /// [signature] - The 64-byte signature to verify.
  /// [publicKey] - The 32-byte Ed25519 public key.
  ///
  /// Returns true if the signature is valid.
  Future<bool> verify({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    if (publicKey.length != CryptoConstants.ed25519PublicKeySize) {
      throw const InvalidKeyException(
        'Ed25519 public key must be 32 bytes',
      );
    }

    if (signature.length != CryptoConstants.ed25519SignatureSize) {
      return false;
    }

    try {
      final simplePublicKey = SimplePublicKey(
        publicKey,
        type: KeyPairType.ed25519,
      );

      final sig = Signature(
        signature,
        publicKey: simplePublicKey,
      );

      return await _algorithm.verify(message, signature: sig);
    } on Exception {
      // Any exception during verification means invalid signature
      return false;
    }
  }

  /// Verifies a signature and throws if invalid.
  ///
  /// Convenience method that throws [SignatureVerificationException]
  /// instead of returning false.
  Future<void> verifyOrThrow({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    final isValid = await verify(
      message: message,
      signature: signature,
      publicKey: publicKey,
    );
    if (!isValid) {
      throw const SignatureVerificationException();
    }
  }
}
