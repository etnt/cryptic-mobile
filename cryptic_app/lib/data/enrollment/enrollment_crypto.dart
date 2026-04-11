// lib/data/enrollment/enrollment_crypto.dart
//
// Cryptographic operations for enrollment:
// - Argon2id key derivation from passphrase
// - HMAC-SHA256 verification
// - AES-256-CBC decryption
// - Ed25519 CSR signing

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

import '../crypto/primitives/ed25519_service.dart';
import 'enrollment_payload.dart';

/// Cryptographic operations for the enrollment flow.
class EnrollmentCrypto {
  EnrollmentCrypto({Ed25519Service? ed25519Service})
      : _ed25519 = ed25519Service ?? Ed25519Service();

  final Ed25519Service _ed25519;

  /// Argon2id parameters (must match the admin tool).
  static const int _argon2Memory = 65536; // 64 MiB
  static const int _argon2Iterations = 3;
  static const int _argon2Parallelism = 4;
  static const int _argon2HashLength = 64; // 32 enc + 32 hmac

  /// Decrypt an enrollment envelope using the user-supplied passphrase.
  ///
  /// 1. Derive 64 bytes via Argon2id(passphrase, salt)
  /// 2. Split into ENC_KEY (32 bytes) and HMAC_KEY (32 bytes)
  /// 3. Verify HMAC-SHA256 over the base64-encoded ciphertext
  /// 4. Decrypt AES-256-CBC
  /// 5. Parse and return the enrollment payload
  Future<EnrollmentPayload> decryptEnvelope(
    EnrollmentEnvelope envelope,
    String passphrase,
  ) async {
    // Step 1: Derive keys from passphrase
    final derived = await _deriveKeys(passphrase, envelope.salt);
    final encKey = derived.sublist(0, 32);
    final hmacKey = derived.sublist(32, 64);

    try {
      // Step 2: Verify HMAC over the base64-encoded ciphertext string
      _verifyHmac(
        hmacKey: hmacKey,
        ciphertextBase64: envelope.ciphertextBase64,
        expectedHmac: envelope.hmac,
      );

      // Step 3: Decrypt AES-256-CBC
      final plaintext = _decryptAesCbc(
        key: encKey,
        iv: envelope.iv,
        ciphertext: envelope.ciphertext,
      );

      // Step 4: Parse JSON payload
      final json = utf8.decode(plaintext);
      return EnrollmentPayload.fromJson(json);
    } finally {
      // Erase derived key material
      encKey.fillRange(0, encKey.length, 0);
      hmacKey.fillRange(0, hmacKey.length, 0);
      derived.fillRange(0, derived.length, 0);
    }
  }

  /// Sign a CSR PEM string with the enrollment secret key.
  ///
  /// Returns the 64-byte Ed25519 signature.
  Future<Uint8List> signCsr(
    String csrPem,
    Uint8List enrollmentSecretKey,
  ) async {
    final csrBytes = Uint8List.fromList(utf8.encode(csrPem));
    return _ed25519.sign(
      message: csrBytes,
      privateKey: enrollmentSecretKey,
    );
  }

  /// Compute the enrollment fingerprint from an Ed25519 public key.
  ///
  /// Returns SHA-256 hex digest (64 chars), matching the server's lookup key.
  String computeEnrollmentFingerprint(Uint8List publicKey) {
    final digest = pc.SHA256Digest();
    final hash = digest.process(publicKey);
    return _hexEncode(hash);
  }

  /// Derive encryption and HMAC keys from passphrase using Argon2id.
  Future<Uint8List> _deriveKeys(String passphrase, Uint8List salt) async {
    final algorithm = crypto.Argon2id(
      memory: _argon2Memory,
      iterations: _argon2Iterations,
      parallelism: _argon2Parallelism,
      hashLength: _argon2HashLength,
    );

    final secretKey = await algorithm.deriveKey(
      secretKey: crypto.SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );

    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Verify HMAC-SHA256 over the base64-encoded ciphertext.
  void _verifyHmac({
    required Uint8List hmacKey,
    required String ciphertextBase64,
    required Uint8List expectedHmac,
  }) {
    final hmac = pc.HMac(pc.SHA256Digest(), 64);
    hmac.init(pc.KeyParameter(hmacKey));

    final data = Uint8List.fromList(utf8.encode(ciphertextBase64));
    final computed = hmac.process(data);

    if (!_constantTimeEquals(computed, expectedHmac)) {
      throw const EnrollmentException(
        'HMAC verification failed — wrong passphrase or tampered data',
      );
    }
  }

  /// Decrypt AES-256-CBC with PKCS7 padding.
  Uint8List _decryptAesCbc({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List ciphertext,
  }) {
    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(
        false, // decrypt
        pc.ParametersWithIV(pc.KeyParameter(key), iv),
      );

    final output = Uint8List(ciphertext.length);
    var offset = 0;
    while (offset < ciphertext.length) {
      offset += cipher.processBlock(ciphertext, offset, output, offset);
    }

    // Remove PKCS7 padding
    return _removePkcs7Padding(output);
  }

  /// Remove PKCS7 padding from decrypted data.
  Uint8List _removePkcs7Padding(Uint8List data) {
    if (data.isEmpty) {
      throw const EnrollmentException('Empty decrypted data');
    }
    final padLen = data.last;
    if (padLen == 0 || padLen > 16 || padLen > data.length) {
      throw const EnrollmentException('Invalid PKCS7 padding');
    }
    // Verify all padding bytes
    for (var i = data.length - padLen; i < data.length; i++) {
      if (data[i] != padLen) {
        throw const EnrollmentException('Invalid PKCS7 padding bytes');
      }
    }
    return data.sublist(0, data.length - padLen);
  }

  /// Constant-time byte array comparison to prevent timing attacks.
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  static String _hexEncode(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
