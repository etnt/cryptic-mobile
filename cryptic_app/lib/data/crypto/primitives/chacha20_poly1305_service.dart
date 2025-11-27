// lib/data/crypto/primitives/chacha20_poly1305_service.dart
//
// ChaCha20-Poly1305 Authenticated Encryption with Associated Data (AEAD)
//
// Used for:
// - Message encryption in Double Ratchet
// - Key bundle encryption at rest
// - Any authenticated encryption needs
//

import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/constants/crypto_constants.dart';
import '../../../core/errors/app_exceptions.dart';

/// Result of an encryption operation.
class EncryptionResult {
  /// Creates an encryption result.
  const EncryptionResult({
    required this.ciphertext,
    required this.nonce,
    required this.tag,
  });

  /// The encrypted data (same length as plaintext).
  final Uint8List ciphertext;

  /// The 12-byte nonce used for encryption.
  final Uint8List nonce;

  /// The 16-byte authentication tag.
  final Uint8List tag;

  /// Returns ciphertext with tag appended (common format).
  Uint8List get ciphertextWithTag {
    final result = Uint8List(ciphertext.length + tag.length);
    result.setRange(0, ciphertext.length, ciphertext);
    result.setRange(ciphertext.length, result.length, tag);
    return result;
  }
}

/// Service for ChaCha20-Poly1305 authenticated encryption.
///
/// Provides:
/// - Authenticated encryption with associated data (AEAD)
/// - Secure nonce generation
/// - Decryption with authentication verification
///
/// This cipher is used throughout Cryptic for message encryption
/// due to its speed and security properties.
class ChaCha20Poly1305Service {
  /// Creates a new ChaCha20-Poly1305 service instance.
  ChaCha20Poly1305Service()
      : _algorithm = Chacha20.poly1305Aead(),
        _random = Random.secure();

  final Chacha20 _algorithm;
  final Random _random;

  /// Generates a cryptographically secure random nonce.
  ///
  /// Returns a 12-byte nonce suitable for ChaCha20-Poly1305.
  Uint8List generateNonce() {
    final nonce = Uint8List(CryptoConstants.chaChaNonceSize);
    for (var i = 0; i < nonce.length; i++) {
      nonce[i] = _random.nextInt(256);
    }
    return nonce;
  }

  /// Encrypts plaintext with ChaCha20-Poly1305.
  ///
  /// [plaintext] - The data to encrypt.
  /// [key] - The 32-byte encryption key.
  /// [nonce] - Optional 12-byte nonce. If not provided, one is generated.
  /// [associatedData] - Optional additional data to authenticate but not encrypt.
  ///
  /// Returns an [EncryptionResult] containing ciphertext, nonce, and tag.
  Future<EncryptionResult> encrypt({
    required Uint8List plaintext,
    required Uint8List key,
    Uint8List? nonce,
    Uint8List? associatedData,
  }) async {
    if (key.length != CryptoConstants.chaChaKeySize) {
      throw const InvalidKeyException(
        'ChaCha20-Poly1305 key must be 32 bytes',
      );
    }

    final effectiveNonce = nonce ?? generateNonce();

    if (effectiveNonce.length != CryptoConstants.chaChaNonceSize) {
      throw const InvalidKeyException(
        'ChaCha20-Poly1305 nonce must be 12 bytes',
      );
    }

    final secretKey = SecretKey(key);
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: effectiveNonce,
      aad: associatedData ?? Uint8List(0),
    );

    return EncryptionResult(
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      nonce: effectiveNonce,
      tag: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  /// Decrypts ciphertext with ChaCha20-Poly1305.
  ///
  /// [ciphertext] - The encrypted data.
  /// [key] - The 32-byte encryption key.
  /// [nonce] - The 12-byte nonce used during encryption.
  /// [tag] - The 16-byte authentication tag.
  /// [associatedData] - Optional additional authenticated data.
  ///
  /// Returns the decrypted plaintext.
  ///
  /// Throws [DecryptionException] if authentication fails.
  Future<Uint8List> decrypt({
    required Uint8List ciphertext,
    required Uint8List key,
    required Uint8List nonce,
    Uint8List? tag,
    Uint8List? associatedData,
  }) async {
    if (key.length != CryptoConstants.chaChaKeySize) {
      throw const InvalidKeyException(
        'ChaCha20-Poly1305 key must be 32 bytes',
      );
    }

    if (nonce.length != CryptoConstants.chaChaNonceSize) {
      throw const InvalidKeyException(
        'ChaCha20-Poly1305 nonce must be 12 bytes',
      );
    }

    // If tag is null, extract it from ciphertext (appended format)
    Uint8List actualCiphertext;
    Uint8List actualTag;
    if (tag == null) {
      if (ciphertext.length < CryptoConstants.chaChaTagSize) {
        throw const DecryptionException('Ciphertext too short');
      }
      final tagStart = ciphertext.length - CryptoConstants.chaChaTagSize;
      actualCiphertext = ciphertext.sublist(0, tagStart);
      actualTag = ciphertext.sublist(tagStart);
    } else {
      actualCiphertext = ciphertext;
      actualTag = tag;
      if (actualTag.length != CryptoConstants.chaChaTagSize) {
        throw const InvalidKeyException(
          'ChaCha20-Poly1305 tag must be 16 bytes',
        );
      }
    }

    try {
      final secretKey = SecretKey(key);
      final secretBox = SecretBox(
        actualCiphertext,
        nonce: nonce,
        mac: Mac(actualTag),
      );

      final plaintext = await _algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: associatedData ?? Uint8List(0),
      );

      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      throw const DecryptionException('Authentication failed');
    } on Exception catch (e) {
      throw DecryptionException('Decryption failed: $e');
    }
  }

  /// Decrypts ciphertext where tag is appended to ciphertext.
  ///
  /// This is a common format where the last 16 bytes are the tag.
  Future<Uint8List> decryptWithAppendedTag({
    required Uint8List ciphertextWithTag,
    required Uint8List key,
    required Uint8List nonce,
    Uint8List? associatedData,
  }) async {
    if (ciphertextWithTag.length < CryptoConstants.chaChaTagSize) {
      throw const DecryptionException('Ciphertext too short');
    }

    final tagStart = ciphertextWithTag.length - CryptoConstants.chaChaTagSize;
    final ciphertext = ciphertextWithTag.sublist(0, tagStart);
    final tag = ciphertextWithTag.sublist(tagStart);

    return decrypt(
      ciphertext: ciphertext,
      key: key,
      nonce: nonce,
      tag: tag,
      associatedData: associatedData,
    );
  }
}
