/// Session manager for CrypticEngine.
///
/// Manages Double Ratchet sessions for each peer, including:
/// - Session creation (from X3DH output)
/// - Session state persistence
/// - Session lookup and iteration
library;

import 'dart:typed_data';

import '../crypto/ratchet/double_ratchet.dart';
import '../crypto/ratchet/ratchet_message.dart';
import '../crypto/ratchet/ratchet_state.dart';
import '../storage/repositories/session_repository.dart';
import 'engine_state.dart';

/// Manages peer sessions for the CrypticEngine.
///
/// Handles:
/// - Creating new sessions from X3DH key agreement
/// - Loading existing sessions from storage
/// - Saving session state after ratchet operations
/// - Session lifecycle (creation, update, removal)
class SessionManager {
  /// Creates a session manager.
  SessionManager({
    required SessionRepository sessionRepository,
    DoubleRatchet? doubleRatchet,
  })  : _sessionRepository = sessionRepository,
        _doubleRatchet = doubleRatchet ?? DoubleRatchet();

  final SessionRepository _sessionRepository;
  final DoubleRatchet _doubleRatchet;
  final Map<String, RatchetState> _sessions = {};
  String? _currentUsername;

  /// Initialize the session manager for a user.
  Future<void> initialize(String username) async {
    _currentUsername = username;
    _sessions.clear();
  }

  /// Dispose the session manager.
  ///
  /// Saves all in-memory sessions to storage before clearing.
  Future<void> dispose() async {
    // Persist any in-memory session state before clearing.
    for (final entry in _sessions.entries) {
      await _saveSession(entry.key, entry.value);
    }
    _sessions.clear();
    _currentUsername = null;
  }

  /// Get list of peer usernames with sessions.
  List<String> get peerUsernames => _sessions.keys.toList();

  /// Check if a session exists for a peer.
  bool hasSession(String peerUsername) => _sessions.containsKey(peerUsername);

  /// Get session info for a peer.
  PeerSession? getSessionInfo(String peerUsername) {
    final state = _sessions[peerUsername];
    if (state == null) return null;

    return PeerSession(
      peerUsername: peerUsername,
      hasSession: true,
      messageCount: state.sendMessageNumber,
    );
  }

  /// Get all session infos.
  Map<String, PeerSession> getAllSessionInfos() => {
        for (final entry in _sessions.entries)
          entry.key: PeerSession(
            peerUsername: entry.key,
            hasSession: true,
            messageCount: entry.value.sendMessageNumber,
          ),
      };

  // ─────────────────────────────────────────────────────────────────────────
  // Session Creation
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a session as the initiator (after X3DH).
  ///
  /// Called after performing X3DH as Alice (initiator).
  /// [peerUsername] - The peer's username.
  /// [sharedSecret] - The shared secret from X3DH.
  /// [ourDhKeyPair] - Our DH keypair (from X3DH ephemeral).
  Future<RatchetState> createSessionAsInitiator({
    required String peerUsername,
    required Uint8List sharedSecret,
    required (Uint8List, Uint8List) ourDhKeyPair,
  }) async {
    if (_currentUsername == null) {
      throw StateError('SessionManager not initialized');
    }

    // Initialize Double Ratchet as Alice (initiator)
    final state = await _doubleRatchet.initSender(
      rootKey: sharedSecret,
      dhKeyPair: ourDhKeyPair,
    );

    _sessions[peerUsername] = state;

    // Persist session state
    await _saveSession(peerUsername, state);

    return state;
  }

  /// Create a session as the responder (from X3DH initial message).
  ///
  /// Called when receiving an X3DH initial message as Bob (responder).
  /// [peerUsername] - The peer's username.
  /// [sharedSecret] - The shared secret from X3DH.
  /// [ourDhKeyPair] - Our signed prekey (used as initial ratchet key).
  /// [theirDhPublic] - Sender's ephemeral DH public key.
  Future<RatchetState> createSessionAsResponder({
    required String peerUsername,
    required Uint8List sharedSecret,
    required (Uint8List, Uint8List) ourDhKeyPair,
    required Uint8List theirDhPublic,
  }) async {
    if (_currentUsername == null) {
      throw StateError('SessionManager not initialized');
    }

    // Initialize Double Ratchet as Bob (responder)
    var state = await _doubleRatchet.initReceiver(
      rootKey: sharedSecret,
      dhKeyPair: ourDhKeyPair,
    );

    // Set the remote DH public key from X3DH
    state = state.copyWith(dhRemote: theirDhPublic);

    _sessions[peerUsername] = state;

    // Persist session state
    await _saveSession(peerUsername, state);

    return state;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session Loading
  // ─────────────────────────────────────────────────────────────────────────

  /// Load a session from storage.
  ///
  /// Returns null if no session exists.
  Future<RatchetState?> loadSession(String peerUsername) async {
    if (_currentUsername == null) {
      throw StateError('SessionManager not initialized');
    }

    // Check memory cache first
    if (_sessions.containsKey(peerUsername)) {
      return _sessions[peerUsername];
    }

    // Try to load from storage
    final state = await _sessionRepository.loadSession(
      peerUsername: peerUsername,
    );

    if (state == null) return null;

    _sessions[peerUsername] = state;
    return state;
  }

  /// Load all sessions from storage.
  Future<void> loadAllSessions() async {
    if (_currentUsername == null) {
      throw StateError('SessionManager not initialized');
    }

    final peers = await _sessionRepository.listPeers();
    print(
        '[SessionManager] loadAllSessions: found ${peers.length} peers: $peers');

    for (final peer in peers) {
      try {
        final state = await _sessionRepository.loadSession(peerUsername: peer);
        if (state != null) {
          _sessions[peer] = state;
          print('[SessionManager] Loaded session for $peer '
              '(send#=${state.sendMessageNumber}, recv#=${state.recvMessageNumber}, '
              'dhStep=${state.dhRatchetStep})');
        } else {
          print('[SessionManager] Session for $peer was null');
        }
      } catch (e) {
        print('[SessionManager] Failed to load session for $peer: $e');
        print('[SessionManager] Removing corrupted session for $peer');
        try {
          await _sessionRepository.deleteSession(peerUsername: peer);
        } catch (deleteError) {
          print(
              '[SessionManager] Could not delete session for $peer: $deleteError');
        }
      }
    }

    print('[SessionManager] loadAllSessions complete: '
        '${_sessions.length} sessions loaded');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Encryption / Decryption
  // ─────────────────────────────────────────────────────────────────────────

  /// Encrypt a message for a peer.
  ///
  /// Returns the encrypted RatchetMessage.
  /// Throws if no session exists.
  Future<RatchetMessage> encryptMessage({
    required String peerUsername,
    required Uint8List plaintext,
  }) async {
    final state = await _getOrLoadSession(peerUsername);
    if (state == null) {
      throw SessionNotFoundException(peerUsername);
    }

    final (message, newState) = await _doubleRatchet.encryptMessage(
      plaintext: plaintext,
      state: state,
    );

    // Update in-memory cache and persist
    _sessions[peerUsername] = newState;
    await _saveSession(peerUsername, newState);

    return message;
  }

  /// Decrypt a message from a peer.
  ///
  /// Returns the decrypted plaintext.
  /// Throws if no session exists or decryption fails.
  Future<Uint8List> decryptMessage({
    required String peerUsername,
    required RatchetMessage message,
  }) async {
    final state = await _getOrLoadSession(peerUsername);
    if (state == null) {
      throw SessionNotFoundException(peerUsername);
    }

    final (plaintext, newState) = await _doubleRatchet.decryptMessage(
      message: message,
      state: state,
    );

    // Update in-memory cache and persist
    _sessions[peerUsername] = newState;
    await _saveSession(peerUsername, newState);

    return plaintext;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session Management
  // ─────────────────────────────────────────────────────────────────────────

  /// Delete a session.
  Future<void> deleteSession(String peerUsername) async {
    _sessions.remove(peerUsername);

    if (_currentUsername != null) {
      await _sessionRepository.deleteSession(peerUsername: peerUsername);
    }
  }

  /// Delete all sessions.
  Future<void> deleteAllSessions() async {
    _sessions.clear();

    if (_currentUsername != null) {
      await _sessionRepository.deleteAllSessions();
    }
  }

  /// Get the current DH public key for a session.
  ///
  /// Returns null if no session exists.
  Uint8List? getCurrentDhPublic(String peerUsername) {
    final state = _sessions[peerUsername];
    return state?.dhSelf.$1;
  }

  /// Get diagnostic info for a single peer session.
  ///
  /// Returns null if no session exists. Exposes ratchet counters
  /// and timestamps without leaking key material.
  Map<String, dynamic>? getSessionDiagnostics(String peerUsername) {
    final state = _sessions[peerUsername];
    if (state == null) return null;

    return {
      'peer': peerUsername,
      'dh_ratchet_step': state.dhRatchetStep,
      'send_message_number': state.sendMessageNumber,
      'recv_message_number': state.recvMessageNumber,
      'sending_chain_active': state.sendingChainActive,
      'receiving_chain_active': state.receivingChainActive,
      'skipped_keys_count': state.skippedKeys.length,
      'created_at': state.createdAt.toIso8601String(),
      'last_updated': state.lastUpdated.toIso8601String(),
    };
  }

  /// Get diagnostics for all sessions.
  Map<String, Map<String, dynamic>> getAllSessionDiagnostics() => {
        for (final peer in _sessions.keys)
          if (getSessionDiagnostics(peer) case final diag?) peer: diag,
      };

  // ─────────────────────────────────────────────────────────────────────────
  // Private Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<RatchetState?> _getOrLoadSession(String peerUsername) async {
    if (_sessions.containsKey(peerUsername)) {
      return _sessions[peerUsername];
    }
    return loadSession(peerUsername);
  }

  Future<void> _saveSession(String peerUsername, RatchetState state) async {
    if (_currentUsername == null) return;

    await _sessionRepository.saveSession(
      peerUsername: peerUsername,
      state: state,
    );
  }
}

/// Exception thrown when a session is not found.
class SessionNotFoundException implements Exception {
  /// Creates a session not found exception.
  SessionNotFoundException(this.peerUsername);

  /// The peer username.
  final String peerUsername;

  @override
  String toString() => 'SessionNotFoundException: No session for $peerUsername';
}
