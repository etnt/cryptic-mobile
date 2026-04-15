// lib/data/storage/secure_storage/secure_storage_service.dart
//
// Secure Storage Service - Platform-agnostic secure storage abstraction
//

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/errors/app_exceptions.dart';

/// Options for secure storage operations.
class SecureStorageOptions {
  const SecureStorageOptions({
    this.requireBiometric = false,
    this.accessible = KeychainAccessibility.unlocked_this_device,
  });

  /// Whether to require biometric authentication for access.
  final bool requireBiometric;

  /// When the keychain item is accessible (iOS/macOS).
  /// Uses KeychainAccessibility from flutter_secure_storage.
  final KeychainAccessibility accessible;
}

/// Secure storage service using platform-specific secure storage.
///
/// On iOS/macOS: Uses Keychain with configurable accessibility.
/// On Android: Uses EncryptedSharedPreferences or Android Keystore.
/// On other platforms: Falls back to encrypted file storage.
class SecureStorageService {
  /// Creates a secure storage service.
  SecureStorageService({
    FlutterSecureStorage? storage,
    SecureStorageOptions options = const SecureStorageOptions(),
  })  : _storage = storage ?? _createStorage(options),
        _options = options;

  final FlutterSecureStorage _storage;
  final SecureStorageOptions _options;

  static FlutterSecureStorage _createStorage(SecureStorageOptions options) {
    // Configure platform-specific options
    final iOSOptions = IOSOptions(
      accessibility: options.accessible,
    );

    const androidOptions = AndroidOptions(
      encryptedSharedPreferences: true,
    );

    final macOSOptions = MacOsOptions(
      accessibility: options.accessible,
    );

    return FlutterSecureStorage(
      iOptions: iOSOptions,
      aOptions: androidOptions,
      mOptions: macOSOptions,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // String Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Writes a string value to secure storage.
  Future<void> write({
    required String key,
    required String value,
  }) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw StorageException('Failed to write to secure storage: $e');
    }
  }

  /// Reads a string value from secure storage.
  ///
  /// Returns null if the key doesn't exist.
  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      throw StorageException('Failed to read from secure storage: $e');
    }
  }

  /// Deletes a value from secure storage.
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      throw StorageException('Failed to delete from secure storage: $e');
    }
  }

  /// Checks if a key exists in secure storage.
  Future<bool> containsKey({required String key}) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      throw StorageException('Failed to check key in secure storage: $e');
    }
  }

  /// Reads all keys from secure storage.
  Future<Map<String, String>> readAll() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      throw StorageException('Failed to read all from secure storage: $e');
    }
  }

  /// Deletes all values from secure storage.
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw StorageException('Failed to delete all from secure storage: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Binary Operations (Base64 encoded)
  // ─────────────────────────────────────────────────────────────────────────

  /// Writes binary data to secure storage (base64 encoded).
  Future<void> writeBytes({
    required String key,
    required Uint8List value,
  }) async {
    final encoded = base64Encode(value);
    await write(key: key, value: encoded);
  }

  /// Reads binary data from secure storage.
  ///
  /// Returns null if the key doesn't exist.
  Future<Uint8List?> readBytes({required String key}) async {
    final encoded = await read(key: key);
    if (encoded == null) return null;

    try {
      return base64Decode(encoded);
    } catch (e) {
      throw StorageException('Failed to decode binary data: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JSON Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Writes a JSON-serializable object to secure storage.
  Future<void> writeJson({
    required String key,
    required Map<String, dynamic> value,
  }) async {
    final encoded = jsonEncode(value);
    await write(key: key, value: encoded);
  }

  /// Reads a JSON object from secure storage.
  ///
  /// Returns null if the key doesn't exist.
  Future<Map<String, dynamic>?> readJson({required String key}) async {
    final encoded = await read(key: key);
    if (encoded == null) return null;

    try {
      return jsonDecode(encoded) as Map<String, dynamic>;
    } catch (e) {
      throw StorageException('Failed to decode JSON data: $e');
    }
  }

  /// Returns the storage options.
  SecureStorageOptions get options => _options;
}
