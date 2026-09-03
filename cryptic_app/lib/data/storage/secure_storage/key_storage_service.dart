// lib/data/storage/secure_storage/key_storage_service.dart
//
// Key Storage Service - Secure storage for cryptographic keys
//

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/errors/app_exceptions.dart';
import '../../crypto/keys/identity_key_pair.dart';
import '../../crypto/keys/key_bundle.dart';
import '../../crypto/keys/one_time_prekey.dart';
import '../../crypto/keys/signed_prekey.dart';
import '../../crypto/ratchet/ratchet_state.dart';
import 'secure_storage_service.dart';

/// Storage keys for identity and session data.
abstract class KeyStorageKeys {
  /// Prefix for all key storage entries.
  static const prefix = 'cryptic_';

  /// Identity key pair storage key.
  static const identityKeys = '${prefix}identity_keys';

  /// Signed prekey storage key.
  static const signedPrekey = '${prefix}signed_prekey';

  /// One-time prekeys storage key.
  static const oneTimePrekeys = '${prefix}one_time_prekeys';

  /// Full key bundle storage key.
  static const keyBundle = '${prefix}key_bundle';

  /// Username storage key.
  static const username = '${prefix}username';

  /// Server info storage key.
  static const serverInfo = '${prefix}server_info';

  /// Session state prefix (appended with peer username).
  static const sessionPrefix = '${prefix}session_';

  /// Creates a session storage key for a peer.
  static String sessionKey(String peerUsername) =>
      '$sessionPrefix$peerUsername';

  /// Pending one-time prekey IDs.
  static const pendingOtpkIds = '${prefix}pending_otpk_ids';
}

/// Service for securely storing cryptographic keys.
///
/// Provides methods to store and retrieve:
/// - Identity key pairs (Ed25519 signing + X25519 DH)
/// - Signed prekeys
/// - One-time prekeys
/// - Session states (Double Ratchet)
class KeyStorageService {
  /// Creates a key storage service.
  KeyStorageService({
    SecureStorageService? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageService();

  final SecureStorageService _secureStorage;

  // ─────────────────────────────────────────────────────────────────────────
  // Identity Keys
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves the identity key pair.
  Future<void> saveIdentityKeyPair(IdentityKeyPair keyPair) async {
    await _secureStorage.writeJson(
      key: KeyStorageKeys.identityKeys,
      value: keyPair.toMap(),
    );
  }

  /// Loads the identity key pair.
  ///
  /// Returns null if no identity keys are stored, or if the stored value
  /// is corrupt / undecryptable (e.g. a stale encryption envelope left over
  /// from a previous enrollment). In the corrupt case the bad entry is
  /// discarded so fresh keys can be regenerated instead of crashing with a
  /// null type-cast.
  Future<IdentityKeyPair?> loadIdentityKeyPair() async {
    final map = await _secureStorage.readJson(
      key: KeyStorageKeys.identityKeys,
    );
    if (map == null) return null;
    if (map['sign_public_key'] is! String) {
      await _secureStorage.delete(key: KeyStorageKeys.identityKeys);
      return null;
    }
    return IdentityKeyPair.fromMap(map);
  }

  /// Checks if valid identity keys exist.
  ///
  /// Validates by loading so a corrupt blob is treated as "no keys",
  /// allowing the engine to regenerate a fresh identity.
  Future<bool> hasIdentityKeys() async =>
      (await loadIdentityKeyPair()) != null;

  /// Deletes the identity key pair.
  Future<void> deleteIdentityKeyPair() async {
    await _secureStorage.delete(key: KeyStorageKeys.identityKeys);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Signed Prekey
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves the signed prekey.
  Future<void> saveSignedPrekey(SignedPrekey prekey) async {
    await _secureStorage.writeJson(
      key: KeyStorageKeys.signedPrekey,
      value: prekey.toMap(),
    );
  }

  /// Loads the signed prekey.
  ///
  /// Returns null if no signed prekey is stored.
  Future<SignedPrekey?> loadSignedPrekey() async {
    final map = await _secureStorage.readJson(
      key: KeyStorageKeys.signedPrekey,
    );
    if (map == null) return null;
    return SignedPrekey.fromMap(map);
  }

  /// Deletes the signed prekey.
  Future<void> deleteSignedPrekey() async {
    await _secureStorage.delete(key: KeyStorageKeys.signedPrekey);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // One-Time Prekeys
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves one-time prekeys.
  Future<void> saveOneTimePrekeys(List<OneTimePrekey> prekeys) async {
    final list = prekeys.map((p) => p.toMap()).toList();
    await _secureStorage.write(
      key: KeyStorageKeys.oneTimePrekeys,
      value: jsonEncode(list),
    );
  }

  /// Loads one-time prekeys.
  ///
  /// Returns empty list if none stored.
  Future<List<OneTimePrekey>> loadOneTimePrekeys() async {
    final encoded = await _secureStorage.read(
      key: KeyStorageKeys.oneTimePrekeys,
    );
    if (encoded == null) return [];

    try {
      final list = jsonDecode(encoded) as List<dynamic>;
      return list
          .map((m) => OneTimePrekey.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw StorageException('Failed to load one-time prekeys: $e');
    }
  }

  /// Adds new one-time prekeys to storage.
  Future<void> addOneTimePrekeys(List<OneTimePrekey> newPrekeys) async {
    final existing = await loadOneTimePrekeys();
    existing.addAll(newPrekeys);
    await saveOneTimePrekeys(existing);
  }

  /// Removes a one-time prekey by ID (after use).
  Future<void> removeOneTimePrekey(int keyId) async {
    final prekeys = await loadOneTimePrekeys();
    prekeys.removeWhere((p) => p.keyId == keyId);
    await saveOneTimePrekeys(prekeys);
  }

  /// Gets a one-time prekey by ID.
  Future<OneTimePrekey?> getOneTimePrekey(int keyId) async {
    final prekeys = await loadOneTimePrekeys();
    try {
      return prekeys.firstWhere((p) => p.keyId == keyId);
    } catch (_) {
      return null;
    }
  }

  /// Deletes all one-time prekeys.
  Future<void> deleteOneTimePrekeys() async {
    await _secureStorage.delete(key: KeyStorageKeys.oneTimePrekeys);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Key Bundle (Full)
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves the full key bundle.
  Future<void> saveKeyBundle(KeyBundle bundle) async {
    await _secureStorage.writeJson(
      key: KeyStorageKeys.keyBundle,
      value: bundle.toMap(),
    );
  }

  /// Loads the full key bundle.
  ///
  /// Returns null if no bundle is stored.
  Future<KeyBundle?> loadKeyBundle() async {
    final map = await _secureStorage.readJson(
      key: KeyStorageKeys.keyBundle,
    );
    if (map == null) return null;
    return KeyBundle.fromServerResponse(map);
  }

  /// Deletes the key bundle.
  Future<void> deleteKeyBundle() async {
    await _secureStorage.delete(key: KeyStorageKeys.keyBundle);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session State (Double Ratchet)
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves a session state for a peer.
  Future<void> saveSessionState({
    required String peerUsername,
    required RatchetState state,
  }) async {
    await _secureStorage.writeJson(
      key: KeyStorageKeys.sessionKey(peerUsername),
      value: state.toMap(),
    );
  }

  /// Loads a session state for a peer.
  ///
  /// Returns null if no session exists.
  Future<RatchetState?> loadSessionState({
    required String peerUsername,
  }) async {
    final map = await _secureStorage.readJson(
      key: KeyStorageKeys.sessionKey(peerUsername),
    );
    if (map == null) return null;
    return RatchetState.fromMap(map);
  }

  /// Checks if a session exists for a peer.
  Future<bool> hasSession({required String peerUsername}) async => await _secureStorage.containsKey(
      key: KeyStorageKeys.sessionKey(peerUsername),
    );

  /// Deletes a session for a peer.
  Future<void> deleteSession({required String peerUsername}) async {
    await _secureStorage.delete(
      key: KeyStorageKeys.sessionKey(peerUsername),
    );
  }

  /// Lists all peers with stored sessions.
  Future<List<String>> listSessionPeers() async {
    final allKeys = await _secureStorage.readAll();
    const prefix = KeyStorageKeys.sessionPrefix;

    return allKeys.keys
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toList();
  }

  /// Deletes all sessions.
  Future<void> deleteAllSessions() async {
    final peers = await listSessionPeers();
    for (final peer in peers) {
      await deleteSession(peerUsername: peer);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // User Metadata
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves the current username.
  Future<void> saveUsername(String username) async {
    await _secureStorage.write(
      key: KeyStorageKeys.username,
      value: username,
    );
  }

  /// Loads the current username.
  Future<String?> loadUsername() async => await _secureStorage.read(key: KeyStorageKeys.username);

  /// Saves server connection info.
  Future<void> saveServerInfo({
    required String host,
    required int port,
  }) async {
    await _secureStorage.writeJson(
      key: KeyStorageKeys.serverInfo,
      value: {'host': host, 'port': port},
    );
  }

  /// Loads server connection info.
  Future<({String host, int port})?> loadServerInfo() async {
    final map = await _secureStorage.readJson(
      key: KeyStorageKeys.serverInfo,
    );
    if (map == null) return null;
    return (
      host: map['host'] as String,
      port: map['port'] as int,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data Management
  // ─────────────────────────────────────────────────────────────────────────

  /// Deletes all cryptic-related data from secure storage.
  ///
  /// This is a destructive operation that will:
  /// - Delete identity keys
  /// - Delete all prekeys
  /// - Delete all session states
  /// - Delete user metadata
  Future<void> deleteAllData() async {
    // Delete all known keys
    await deleteIdentityKeyPair();
    await deleteSignedPrekey();
    await deleteOneTimePrekeys();
    await deleteKeyBundle();
    await deleteAllSessions();

    // Delete metadata
    await _secureStorage.delete(key: KeyStorageKeys.username);
    await _secureStorage.delete(key: KeyStorageKeys.serverInfo);
    await _secureStorage.delete(key: KeyStorageKeys.pendingOtpkIds);
  }

  /// Checks if the storage has been initialized with keys.
  Future<bool> isInitialized() async => await hasIdentityKeys();
}
