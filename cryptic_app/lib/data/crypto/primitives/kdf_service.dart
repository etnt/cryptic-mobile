// lib/data/crypto/primitives/kdf_service.dart
//
// KDF (Key Derivation Function) Service
//
// Implements libsodium-compatible key derivation using Blake2b.
// This matches the server's crypto_kdf_derive_from_key function.
//

import 'dart:typed_data';

import 'package:pointycastle/digests/blake2b.dart';

import '../../../core/errors/app_exceptions.dart';

/// Service for libsodium-compatible key derivation.
///
/// This implements the same KDF as libsodium's crypto_kdf_derive_from_key,
/// which uses Blake2b with:
/// - Key: master key (32 bytes)
/// - Salt: subkey_id (8 bytes LE) || 8 zero bytes = 16 bytes
/// - Personal: context (8 bytes, zero-padded) || 8 zero bytes = 16 bytes
/// - Message: empty
///
/// From libsodium docs:
/// BLAKE2B-subkeylen(key=key, message={}, salt=subkey_id || {0}, personal=ctx || {0})
///
/// This is critical for interoperability with the Erlang server which uses
/// libsodium for Double Ratchet key derivation.
class KdfService {
  /// Creates a new KDF service instance.
  KdfService();

  /// Derives a key using Blake2b, compatible with libsodium's crypto_kdf_derive_from_key.
  ///
  /// [length] - Output key length in bytes (16-64).
  /// [subkeyId] - Unique subkey identifier (used in salt).
  /// [context] - Domain separation context (max 8 bytes, zero-padded).
  /// [masterKey] - Master key (must be 32 bytes).
  ///
  /// Returns the derived key of specified length.
  Future<Uint8List> deriveKey({
    required int length,
    required int subkeyId,
    required String context,
    required Uint8List masterKey,
  }) async {
    if (length < 16 || length > 64) {
      throw const CryptoException('Key length must be 16-64 bytes');
    }

    if (masterKey.length != 32) {
      throw const CryptoException('Master key must be 32 bytes');
    }

    if (context.length > 8) {
      throw const CryptoException('Context must be max 8 bytes');
    }

    // Build the salt: subkey_id (8 bytes LE) || 8 zero bytes
    final salt = Uint8List(16);
    final saltView = ByteData.view(salt.buffer);
    saltView.setUint64(0, subkeyId, Endian.little);
    // Bytes 8-15 are already zero

    // Build the personalization: context (8 bytes, zero-padded) || 8 zero bytes
    final personalization = Uint8List(16);
    final contextBytes = context.codeUnits;
    for (var i = 0; i < contextBytes.length && i < 8; i++) {
      personalization[i] = contextBytes[i];
    }
    // Bytes 8-15 are already zero

    // Use pointycastle's Blake2bDigest with full parameter support
    // This matches libsodium's crypto_generichash_blake2b_salt_personal
    final blake2b = Blake2bDigest(
      digestSize: length,
      key: masterKey,
      salt: salt,
      personalization: personalization,
    );

    // Hash empty message (libsodium's KDF hashes an empty message)
    final output = Uint8List(length);
    blake2b.doFinal(output, 0);

    return output;
  }

  /// Derives message key and new chain key from current chain key.
  ///
  /// This matches the Erlang server's advance_sending_chain and advance_receiving_chain.
  ///
  /// [chainKey] - Current chain key (32 bytes).
  /// [messageNumber] - Message number in current chain.
  ///
  /// Returns (newChainKey, messageKey).
  Future<(Uint8List, Uint8List)> deriveMessageKey({
    required Uint8List chainKey,
    required int messageNumber,
  }) async {
    // MessageKey = kdf_derive(32, MsgNumber, "msg", ChainKey)
    final messageKey = await deriveKey(
      length: 32,
      subkeyId: messageNumber,
      context: 'msg',
      masterKey: chainKey,
    );

    // NewChainKey = kdf_derive(32, MsgNumber + 1, "chain", ChainKey)
    final newChainKey = await deriveKey(
      length: 32,
      subkeyId: messageNumber + 1,
      context: 'chain',
      masterKey: chainKey,
    );

    return (newChainKey, messageKey);
  }

  /// Derives encryption key from message key.
  ///
  /// This matches the Erlang server's kdf_mk function.
  ///
  /// [messageKey] - The message key (32 bytes).
  ///
  /// Returns the encryption key (32 bytes).
  Future<Uint8List> deriveEncryptionKey({
    required Uint8List messageKey,
  }) async {
    // EncKey = kdf_derive(32, 0, "enc", MessageKey)
    return deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'enc',
      masterKey: messageKey,
    );
  }

  /// Derives root key, initiator chain key, and responder chain key from DH output.
  ///
  /// This matches the Erlang server's kdf_rk function:
  /// 1. MixedKey = RootKey XOR DhOutput
  /// 2. NewRootKey = kdf_derive(32, 0, "root", MixedKey)
  /// 3. InitChainKey = kdf_derive(32, 1, "init", MixedKey)
  /// 4. RespChainKey = kdf_derive(32, 2, "resp", MixedKey)
  ///
  /// [rootKey] - Current root key (32 bytes).
  /// [dhOutput] - DH shared secret (32 bytes).
  ///
  /// Returns (newRootKey, initiatorChainKey, responderChainKey).
  Future<(Uint8List, Uint8List, Uint8List)> deriveRatchetKeys({
    required Uint8List rootKey,
    required Uint8List dhOutput,
  }) async {
    if (rootKey.length != 32 || dhOutput.length != 32) {
      throw const CryptoException('Both rootKey and dhOutput must be 32 bytes');
    }

    // Mix the root key and DH output by XORing them
    final mixedKey = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      mixedKey[i] = rootKey[i] ^ dhOutput[i];
    }

    // NewRootKey = kdf_derive(32, 0, "root", MixedKey)
    final newRootKey = await deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'root',
      masterKey: mixedKey,
    );

    // InitChainKey = kdf_derive(32, 1, "init", MixedKey)
    final initChainKey = await deriveKey(
      length: 32,
      subkeyId: 1,
      context: 'init',
      masterKey: mixedKey,
    );

    // RespChainKey = kdf_derive(32, 2, "resp", MixedKey)
    final respChainKey = await deriveKey(
      length: 32,
      subkeyId: 2,
      context: 'resp',
      masterKey: mixedKey,
    );

    return (newRootKey, initChainKey, respChainKey);
  }
}
