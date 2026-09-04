// lib/data/crypto/primitives/hkdf_service.dart
//
// HKDF (HMAC-based Key Derivation Function) - RFC 5869
//
// Used for:
// - X3DH shared secret derivation
// - Double Ratchet root key and chain key derivation
// - Deriving encryption keys from shared secrets
//

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/constants/crypto_constants.dart';
import '../../../core/errors/app_exceptions.dart';

/// Service for HKDF key derivation operations.
///
/// HKDF is used throughout the Signal protocol to derive cryptographic
/// keys from shared secrets. It consists of two stages:
/// 1. Extract: Derives a pseudorandom key from input keying material
/// 2. Expand: Expands the PRK into output keying material
///
/// This implementation uses HMAC-SHA256 as the underlying hash function.
class HkdfService {
  /// Creates a new HKDF service instance.
  HkdfService();

  /// Derives a key using HKDF.
  ///
  /// [inputKeyMaterial] - The input keying material (e.g., DH shared secret).
  /// [salt] - Optional salt value (32 bytes recommended, can be empty).
  /// [info] - Context/application-specific info string.
  /// [outputLength] - Desired output length in bytes (default 32).
  ///
  /// Returns the derived key material.
  Future<Uint8List> deriveKey({
    required Uint8List inputKeyMaterial,
    required String info,
    Uint8List? salt,
    int outputLength = 32,
  }) async {
    if (inputKeyMaterial.isEmpty) {
      throw const CryptoException('Input key material cannot be empty');
    }

    // Create HKDF with the desired output length
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: outputLength,
    );

    final secretKey = SecretKey(inputKeyMaterial);
    final infoBytes = Uint8List.fromList(info.codeUnits);

    final derivedKey = await hkdf.deriveKey(
      secretKey: secretKey,
      nonce: salt ?? Uint8List(0),
      info: infoBytes,
    );

    final keyBytes = await derivedKey.extractBytes();
    return Uint8List.fromList(keyBytes);
  }

  /// Derives keys for X3DH key agreement.
  ///
  /// Combines multiple DH outputs and derives a shared secret.
  ///
  /// [dhOutputs] - List of DH shared secrets to combine.
  /// [info] - Context string (usually "X3DH" or similar).
  ///
  /// Returns a 32-byte shared secret suitable for initializing Double Ratchet.
  Future<Uint8List> deriveX3dhSecret({
    required List<Uint8List> dhOutputs,
    String info = 'X3DH',
  }) async {
    // Concatenate all DH outputs
    final totalLength = dhOutputs.fold<int>(0, (sum, dh) => sum + dh.length);
    final combined = Uint8List(totalLength);

    var offset = 0;
    for (final dh in dhOutputs) {
      combined.setRange(offset, offset + dh.length, dh);
      offset += dh.length;
    }

    // Use empty salt for X3DH (as per Signal spec)
    return deriveKey(
      inputKeyMaterial: combined,
      salt: Uint8List(CryptoConstants.hkdfSaltSize), // Zero-filled salt
      info: info,
    );
  }

  /// Derives root key and chain key for Double Ratchet.
  ///
  /// This implements the KDF_RK function from the Double Ratchet spec.
  ///
  /// [rootKey] - Current root key (32 bytes).
  /// [dhOutput] - DH output from ratchet step (32 bytes).
  ///
  /// Returns a tuple of (newRootKey, chainKey), each 32 bytes.
  Future<(Uint8List, Uint8List)> deriveRatchetKeys({
    required Uint8List rootKey,
    required Uint8List dhOutput,
  }) async {
    if (rootKey.length != CryptoConstants.hkdfOutputSize) {
      throw const InvalidKeyException('Root key must be 32 bytes');
    }

    if (dhOutput.length != CryptoConstants.x25519SharedSecretSize) {
      throw const InvalidKeyException('DH output must be 32 bytes');
    }

    // Derive 64 bytes: first 32 for new root key, next 32 for chain key
    final output = await deriveKey(
      inputKeyMaterial: dhOutput,
      salt: rootKey,
      info: CryptoConstants.ratchetChainInfo,
      outputLength: 64,
    );

    return (
      output.sublist(0, 32), // New root key
      output.sublist(32, 64), // Chain key
    );
  }

  /// Derives message key from chain key for Double Ratchet.
  ///
  /// This implements the KDF_CK function from the Double Ratchet spec.
  ///
  /// [chainKey] - Current chain key (32 bytes).
  ///
  /// Returns a tuple of (newChainKey, messageKey), each 32 bytes.
  Future<(Uint8List, Uint8List)> deriveMessageKey({
    required Uint8List chainKey,
  }) async {
    if (chainKey.length != CryptoConstants.hkdfOutputSize) {
      throw const InvalidKeyException('Chain key must be 32 bytes');
    }

    // Use HMAC directly for chain key advancement (simpler than HKDF)
    // This matches the Signal spec: CK_new = HMAC(CK, 0x02), MK = HMAC(CK, 0x01)
    final hmac = Hmac.sha256();

    // Message key: HMAC(chain_key, 0x01)
    final messageKeyMac = await hmac.calculateMac(
      [0x01],
      secretKey: SecretKey(chainKey),
    );

    // New chain key: HMAC(chain_key, 0x02)
    final newChainKeyMac = await hmac.calculateMac(
      [0x02],
      secretKey: SecretKey(chainKey),
    );

    return (
      Uint8List.fromList(newChainKeyMac.bytes), // New chain key
      Uint8List.fromList(messageKeyMac.bytes), // Message key
    );
  }

  /// Derives encryption key, nonce, and auth key from message key.
  ///
  /// Expands a 32-byte message key into the components needed for AEAD.
  ///
  /// [messageKey] - The 32-byte message key.
  ///
  /// Returns (encryptionKey, nonce) - 32-byte key and 12-byte nonce.
  Future<(Uint8List, Uint8List)> deriveEncryptionComponents({
    required Uint8List messageKey,
  }) async {
    if (messageKey.length != CryptoConstants.hkdfOutputSize) {
      throw const InvalidKeyException('Message key must be 32 bytes');
    }

    // Derive 44 bytes: 32 for encryption key, 12 for nonce
    final output = await deriveKey(
      inputKeyMaterial: messageKey,
      salt: Uint8List(CryptoConstants.hkdfSaltSize),
      info: CryptoConstants.ratchetMessageInfo,
      outputLength:
          CryptoConstants.chaChaKeySize + CryptoConstants.chaChaNonceSize,
    );

    return (
      output.sublist(0, CryptoConstants.chaChaKeySize), // Encryption key
      output.sublist(
        CryptoConstants.chaChaKeySize,
        CryptoConstants.chaChaKeySize + CryptoConstants.chaChaNonceSize,
      ), // Nonce
    );
  }
}
