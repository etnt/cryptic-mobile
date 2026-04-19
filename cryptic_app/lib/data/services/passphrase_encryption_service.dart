// lib/data/services/passphrase_encryption_service.dart
//
// Passphrase-based encryption layer for stored keys.
//
// After enrollment, the user sets their own passphrase. All sensitive
// data (identity keys, signed prekeys, OTPs, session states, client
// private key PEM) are encrypted with AES-256-CBC using an Argon2id-
// derived key before being written to secure storage.
//
// This adds defence-in-depth on top of the platform keychain so that
// a device backup or keychain export cannot reveal key material
// without the user's passphrase.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

import '../../core/errors/app_exceptions.dart';
import '../storage/secure_storage/secure_storage_service.dart';

/// Storage key for passphrase verification data.
const _kPassphraseVerifier = 'cryptic_passphrase_verifier';

/// Exception thrown when the user supplies the wrong passphrase.
class WrongPassphraseException extends CrypticException {
  const WrongPassphraseException([
    super.message = 'Wrong passphrase',
  ]);
}

/// Envelope produced by [encrypt]. JSON-serialisable.
class EncryptedEnvelope {
  const EncryptedEnvelope({
    required this.salt,
    required this.iv,
    required this.ciphertext,
  });

  factory EncryptedEnvelope.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return EncryptedEnvelope(
      salt: base64Decode(map['salt'] as String),
      iv: base64Decode(map['iv'] as String),
      ciphertext: base64Decode(map['ct'] as String),
    );
  }

  final Uint8List salt;
  final Uint8List iv;
  final Uint8List ciphertext;

  String toJson() => jsonEncode({
        'salt': base64Encode(salt),
        'iv': base64Encode(iv),
        'ct': base64Encode(ciphertext),
      });
}

/// Service that encrypts/decrypts arbitrary strings using a passphrase.
///
/// Uses Argon2id for key derivation and AES-256-CBC for encryption,
/// matching the parameters used by the enrollment crypto module.
class PassphraseEncryptionService {
  PassphraseEncryptionService({
    SecureStorageService? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageService();

  final SecureStorageService _secureStorage;

  // Argon2id parameters – must stay constant across app versions.
  static const int _argon2Memory = 65536; // 64 MiB
  static const int _argon2Iterations = 3;
  static const int _argon2Parallelism = 4;
  static const int _argon2HashLength = 32; // 32-byte AES key

  /// Whether a passphrase has been set (verifier exists in storage).
  Future<bool> isPassphraseSet() async {
    return _secureStorage.containsKey(key: _kPassphraseVerifier);
  }

  /// Store a passphrase verifier so we can validate on login.
  ///
  /// We derive a key from the passphrase with a random salt, then
  /// encrypt a known magic string. On login we re-derive and check
  /// that it decrypts.
  Future<void> setPassphrase(String passphrase) async {
    const magic = 'CRYPTIC_PASSPHRASE_OK';
    final envelope = await encrypt(magic, passphrase);
    await _secureStorage.write(
      key: _kPassphraseVerifier,
      value: envelope.toJson(),
    );
  }

  /// Verify that [passphrase] matches the stored verifier.
  ///
  /// Returns `true` if correct, `false` otherwise.
  Future<bool> verifyPassphrase(String passphrase) async {
    final raw = await _secureStorage.read(key: _kPassphraseVerifier);
    if (raw == null) return false;
    try {
      final envelope = EncryptedEnvelope.fromJson(raw);
      final plaintext = await decrypt(envelope, passphrase);
      return plaintext == 'CRYPTIC_PASSPHRASE_OK';
    } catch (_) {
      return false;
    }
  }

  /// Change the passphrase.
  ///
  /// All stored encrypted values must be re-encrypted by the caller
  /// (e.g. via [reEncryptAll]). This only updates the verifier.
  Future<void> changePassphrase({
    required String oldPassphrase,
    required String newPassphrase,
  }) async {
    final ok = await verifyPassphrase(oldPassphrase);
    if (!ok) throw const WrongPassphraseException();
    await setPassphrase(newPassphrase);
  }

  /// Delete the passphrase verifier (used on account wipe).
  Future<void> deleteVerifier() async {
    await _secureStorage.delete(key: _kPassphraseVerifier);
  }

  // ───────────────────────────────────────────────────────────────────────
  // Encrypt / Decrypt
  // ───────────────────────────────────────────────────────────────────────

  /// Encrypt [plaintext] with [passphrase].
  ///
  /// A fresh random salt and IV are generated each time.
  Future<EncryptedEnvelope> encrypt(
    String plaintext,
    String passphrase,
  ) async {
    final salt = _randomBytes(16);
    final iv = _randomBytes(16);
    final key = await _deriveKey(passphrase, salt);

    try {
      final ct = _aesEncrypt(
        key: key,
        iv: iv,
        plaintext: Uint8List.fromList(utf8.encode(plaintext)),
      );
      return EncryptedEnvelope(salt: salt, iv: iv, ciphertext: ct);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  /// Decrypt an [envelope] using [passphrase].
  ///
  /// Throws [WrongPassphraseException] if decryption fails (bad padding).
  Future<String> decrypt(
    EncryptedEnvelope envelope,
    String passphrase,
  ) async {
    final key = await _deriveKey(passphrase, envelope.salt);

    try {
      final plaintext = _aesDecrypt(
        key: key,
        iv: envelope.iv,
        ciphertext: envelope.ciphertext,
      );
      return utf8.decode(plaintext);
    } on Exception {
      throw const WrongPassphraseException();
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Internals
  // ───────────────────────────────────────────────────────────────────────

  Future<Uint8List> _deriveKey(String passphrase, Uint8List salt) async {
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

  /// AES-256-CBC encrypt with PKCS7 padding.
  Uint8List _aesEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) {
    final padded = _addPkcs7Padding(plaintext, 16);
    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));

    final output = Uint8List(padded.length);
    var offset = 0;
    while (offset < padded.length) {
      offset += cipher.processBlock(padded, offset, output, offset);
    }
    return output;
  }

  /// AES-256-CBC decrypt and strip PKCS7 padding.
  Uint8List _aesDecrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List ciphertext,
  }) {
    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));

    final output = Uint8List(ciphertext.length);
    var offset = 0;
    while (offset < ciphertext.length) {
      offset += cipher.processBlock(ciphertext, offset, output, offset);
    }
    return _removePkcs7Padding(output);
  }

  Uint8List _addPkcs7Padding(Uint8List data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLen);
    padded.setAll(0, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLen;
    }
    return padded;
  }

  Uint8List _removePkcs7Padding(Uint8List data) {
    if (data.isEmpty) {
      throw const WrongPassphraseException('Decrypted data is empty');
    }
    final padLen = data.last;
    if (padLen == 0 || padLen > 16 || padLen > data.length) {
      throw const WrongPassphraseException();
    }
    for (var i = data.length - padLen; i < data.length; i++) {
      if (data[i] != padLen) {
        throw const WrongPassphraseException();
      }
    }
    return data.sublist(0, data.length - padLen);
  }

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
