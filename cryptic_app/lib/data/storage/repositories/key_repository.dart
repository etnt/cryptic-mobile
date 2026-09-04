// lib/data/storage/repositories/key_repository.dart
//
// Key Repository - Manages cryptographic key persistence
//

import '../../crypto/keys/identity_key_pair.dart';
import '../../crypto/keys/key_bundle.dart';
import '../../crypto/keys/one_time_prekey.dart';
import '../../crypto/keys/signed_prekey.dart';
import '../secure_storage/key_storage_service.dart';

/// Repository for managing cryptographic keys.
///
/// Provides a clean interface for key CRUD operations,
/// abstracting the underlying secure storage implementation.
class KeyRepository {
  /// Creates a key repository.
  KeyRepository({
    KeyStorageService? keyStorage,
  }) : _keyStorage = keyStorage ?? KeyStorageService();

  final KeyStorageService _keyStorage;

  // ─────────────────────────────────────────────────────────────────────────
  // Identity Keys
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves identity key pair.
  Future<void> saveIdentityKeys(IdentityKeyPair keyPair) async {
    await _keyStorage.saveIdentityKeyPair(keyPair);
  }

  /// Loads identity key pair.
  Future<IdentityKeyPair?> loadIdentityKeys() async =>
      await _keyStorage.loadIdentityKeyPair();

  /// Checks if identity keys exist.
  Future<bool> hasIdentityKeys() async => await _keyStorage.hasIdentityKeys();

  /// Deletes identity keys.
  Future<void> deleteIdentityKeys() async {
    await _keyStorage.deleteIdentityKeyPair();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Signed Prekey
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves signed prekey.
  Future<void> saveSignedPrekey(SignedPrekey prekey) async {
    await _keyStorage.saveSignedPrekey(prekey);
  }

  /// Loads signed prekey.
  Future<SignedPrekey?> loadSignedPrekey() async =>
      await _keyStorage.loadSignedPrekey();

  /// Deletes signed prekey.
  Future<void> deleteSignedPrekey() async {
    await _keyStorage.deleteSignedPrekey();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // One-Time Prekeys
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves one-time prekeys (replaces existing).
  Future<void> saveOneTimePrekeys(List<OneTimePrekey> prekeys) async {
    await _keyStorage.saveOneTimePrekeys(prekeys);
  }

  /// Loads all one-time prekeys.
  Future<List<OneTimePrekey>> loadOneTimePrekeys() async =>
      await _keyStorage.loadOneTimePrekeys();

  /// Adds new one-time prekeys.
  Future<void> addOneTimePrekeys(List<OneTimePrekey> prekeys) async {
    await _keyStorage.addOneTimePrekeys(prekeys);
  }

  /// Removes a used one-time prekey.
  Future<void> consumeOneTimePrekey(int keyId) async {
    await _keyStorage.removeOneTimePrekey(keyId);
  }

  /// Gets a one-time prekey by ID.
  Future<OneTimePrekey?> getOneTimePrekey(int keyId) async =>
      await _keyStorage.getOneTimePrekey(keyId);

  /// Gets the count of remaining one-time prekeys.
  Future<int> getOneTimePrekeyCount() async {
    final prekeys = await loadOneTimePrekeys();
    return prekeys.length;
  }

  /// Deletes all one-time prekeys.
  Future<void> deleteOneTimePrekeys() async {
    await _keyStorage.deleteOneTimePrekeys();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Key Bundle
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves the full key bundle.
  Future<void> saveKeyBundle(KeyBundle bundle) async {
    await _keyStorage.saveKeyBundle(bundle);
  }

  /// Loads the full key bundle.
  Future<KeyBundle?> loadKeyBundle() async => await _keyStorage.loadKeyBundle();

  /// Deletes the key bundle.
  Future<void> deleteKeyBundle() async {
    await _keyStorage.deleteKeyBundle();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Own Key Bundle (Private Keys)
  // ─────────────────────────────────────────────────────────────────────────

  /// Loads the own key bundle with all private keys.
  ///
  /// Constructs an [OwnKeyBundle] from the stored components:
  /// - Identity key pair
  /// - Signed prekey
  /// - One-time prekeys
  ///
  /// Returns null if any required component is missing.
  Future<OwnKeyBundle?> loadOwnKeyBundle() async {
    final identity = await loadIdentityKeys();
    if (identity == null) return null;

    final signedPrekey = await loadSignedPrekey();
    if (signedPrekey == null) return null;

    final oneTimePrekeys = await loadOneTimePrekeys();

    // Convert one-time prekeys list to map by keyId
    final otpkMap = <int, OneTimePrekey>{};
    for (final otpk in oneTimePrekeys) {
      otpkMap[otpk.keyId] = otpk;
    }

    return OwnKeyBundle(
      identity: identity,
      signedPrekey: signedPrekey,
      oneTimePrekeys: otpkMap,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // User Metadata
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves the username.
  Future<void> saveUsername(String username) async {
    await _keyStorage.saveUsername(username);
  }

  /// Loads the username.
  Future<String?> loadUsername() async => await _keyStorage.loadUsername();

  /// Saves server info.
  Future<void> saveServerInfo({
    required String host,
    required int port,
  }) async {
    await _keyStorage.saveServerInfo(host: host, port: port);
  }

  /// Loads server info.
  Future<({String host, int port})?> loadServerInfo() async =>
      await _keyStorage.loadServerInfo();

  // ─────────────────────────────────────────────────────────────────────────
  // Data Management
  // ─────────────────────────────────────────────────────────────────────────

  /// Checks if storage is initialized with keys.
  Future<bool> isInitialized() async => await _keyStorage.isInitialized();

  /// Deletes all stored keys and metadata.
  Future<void> deleteAllData() async {
    await _keyStorage.deleteAllData();
  }

  /// Gets a summary of stored keys (for debugging/UI).
  Future<Map<String, dynamic>> getKeySummary() async {
    final hasIdentity = await hasIdentityKeys();
    final signedPrekey = await loadSignedPrekey();
    final otpkCount = await getOneTimePrekeyCount();
    final username = await loadUsername();
    final serverInfo = await loadServerInfo();

    return {
      'has_identity_keys': hasIdentity,
      'has_signed_prekey': signedPrekey != null,
      'signed_prekey_id': signedPrekey?.keyId,
      'one_time_prekey_count': otpkCount,
      'username': username,
      'server_host': serverInfo?.host,
      'server_port': serverInfo?.port,
    };
  }
}
