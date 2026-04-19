// lib/data/storage/secure_storage/encrypted_secure_storage.dart
//
// Encrypted wrapper around SecureStorageService.
//
// Transparently encrypts sensitive keys on write and decrypts on read
// using the user's passphrase (Argon2id + AES-256-CBC).
//
// Non-sensitive keys pass through unmodified.

import '../../services/passphrase_encryption_service.dart';
import 'secure_storage_service.dart';

/// Set of storage key prefixes whose values must be encrypted.
const _sensitiveKeyPrefixes = {
  'cryptic_identity_keys',
  'cryptic_signed_prekey',
  'cryptic_one_time_prekeys',
  'cryptic_key_bundle',
  'cryptic_cert_client_key',
  'cryptic_session_', // all session states
};

/// A [SecureStorageService] decorator that encrypts/decrypts values
/// for designated sensitive keys before delegating to the inner store.
class EncryptedSecureStorage extends SecureStorageService {
  EncryptedSecureStorage({
    required String passphrase,
  }) : _passphrase = passphrase;

  final String _passphrase;
  final PassphraseEncryptionService _enc = PassphraseEncryptionService();

  bool _isSensitive(String key) =>
      _sensitiveKeyPrefixes.any((p) => key == p || key.startsWith(p));

  @override
  Future<void> write({required String key, required String value}) async {
    if (_isSensitive(key)) {
      final envelope = await _enc.encrypt(value, _passphrase);
      return super.write(key: key, value: envelope.toJson());
    }
    return super.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) async {
    final raw = await super.read(key: key);
    if (raw == null || !_isSensitive(key)) return raw;

    // Attempt to decrypt. If the value is not an encrypted envelope
    // (e.g. legacy plaintext from before passphrase was set), return
    // the raw value so the app doesn't break on first migration.
    try {
      final envelope = EncryptedEnvelope.fromJson(raw);
      return await _enc.decrypt(envelope, _passphrase);
    } on FormatException {
      // Not JSON / not an envelope — legacy plaintext data.
      return raw;
    }
  }
}
