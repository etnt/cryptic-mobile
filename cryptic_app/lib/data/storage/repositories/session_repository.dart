// lib/data/storage/repositories/session_repository.dart
//
// Session Repository - Manages Double Ratchet session persistence
//

import '../../crypto/ratchet/ratchet_state.dart';
import '../secure_storage/key_storage_service.dart';

/// Repository for managing Double Ratchet session states.
///
/// Provides a clean interface for session CRUD operations,
/// abstracting the underlying secure storage implementation.
class SessionRepository {
  /// Creates a session repository.
  SessionRepository({
    KeyStorageService? keyStorage,
  }) : _keyStorage = keyStorage ?? KeyStorageService();

  final KeyStorageService _keyStorage;

  /// Saves a session state for a peer.
  ///
  /// Overwrites any existing session for the peer.
  Future<void> saveSession({
    required String peerUsername,
    required RatchetState state,
  }) async {
    await _keyStorage.saveSessionState(
      peerUsername: peerUsername,
      state: state,
    );
  }

  /// Loads a session state for a peer.
  ///
  /// Returns null if no session exists.
  Future<RatchetState?> loadSession({
    required String peerUsername,
  }) async {
    return await _keyStorage.loadSessionState(peerUsername: peerUsername);
  }

  /// Checks if a session exists for a peer.
  Future<bool> hasSession({required String peerUsername}) async {
    return await _keyStorage.hasSession(peerUsername: peerUsername);
  }

  /// Deletes a session for a peer.
  Future<void> deleteSession({required String peerUsername}) async {
    await _keyStorage.deleteSession(peerUsername: peerUsername);
  }

  /// Lists all peers with active sessions.
  Future<List<String>> listPeers() async {
    return await _keyStorage.listSessionPeers();
  }

  /// Deletes all sessions.
  Future<void> deleteAllSessions() async {
    await _keyStorage.deleteAllSessions();
  }

  /// Gets session info for all peers (for debugging/UI).
  Future<Map<String, Map<String, dynamic>>> getAllSessionInfo() async {
    final peers = await listPeers();
    final info = <String, Map<String, dynamic>>{};

    for (final peer in peers) {
      final session = await loadSession(peerUsername: peer);
      if (session != null) {
        info[peer] = session.getInfo();
      }
    }

    return info;
  }

  /// Cleans up expired skipped keys in all sessions.
  ///
  /// Returns the number of keys removed.
  Future<int> cleanupExpiredKeys() async {
    final peers = await listPeers();
    var totalRemoved = 0;

    for (final peer in peers) {
      final session = await loadSession(peerUsername: peer);
      if (session != null) {
        final keysBeforeCleanup = session.skippedKeys.length;
        session.cleanupExpiredKeys();
        final removed = keysBeforeCleanup - session.skippedKeys.length;

        if (removed > 0) {
          totalRemoved += removed;
          await saveSession(peerUsername: peer, state: session);
        }
      }
    }

    return totalRemoved;
  }
}
