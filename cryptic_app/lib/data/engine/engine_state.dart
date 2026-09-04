/// Engine state management for CrypticEngine.
///
/// Provides immutable state representation for the engine,
/// including connection status, user identity, and sessions.
library;

import 'dart:typed_data';

/// Connection status of the engine.
enum ConnectionStatus {
  /// Not connected to server.
  disconnected,

  /// Currently connecting.
  connecting,

  /// Connected and ready.
  connected,

  /// Reconnecting after disconnect.
  reconnecting,

  /// Connection failed with error.
  error,
}

/// Engine initialization status.
enum EngineStatus {
  /// Engine not initialized.
  uninitialized,

  /// Engine is initializing.
  initializing,

  /// Engine is ready (keys loaded, can connect).
  ready,

  /// Engine needs setup (no identity keys).
  needsSetup,

  /// Engine failed to initialize.
  failed,
}

/// User identity information.
class UserIdentity {
  /// Creates a user identity.
  const UserIdentity({
    required this.username,
    required this.identitySignPublicKey,
    required this.identityDhPublicKey,
  });

  /// The username.
  final String username;

  /// Ed25519 identity signing public key.
  final Uint8List identitySignPublicKey;

  /// X25519 identity DH public key.
  final Uint8List identityDhPublicKey;

  /// Create a copy with updated fields.
  UserIdentity copyWith({
    String? username,
    Uint8List? identitySignPublicKey,
    Uint8List? identityDhPublicKey,
  }) =>
      UserIdentity(
        username: username ?? this.username,
        identitySignPublicKey:
            identitySignPublicKey ?? this.identitySignPublicKey,
        identityDhPublicKey: identityDhPublicKey ?? this.identityDhPublicKey,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserIdentity && other.username == username;
  }

  @override
  int get hashCode => username.hashCode;
}

/// Server configuration.
class ServerConfig {
  /// Creates server configuration.
  const ServerConfig({
    required this.host,
    required this.port,
    this.path = '/ws',
  });

  /// Server hostname.
  final String host;

  /// Server port.
  final int port;

  /// WebSocket path.
  final String path;

  /// Get the full WebSocket URL.
  String get wsUrl => 'wss://$host:$port$path';

  /// Create a copy with updated fields.
  ServerConfig copyWith({
    String? host,
    int? port,
    String? path,
  }) =>
      ServerConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        path: path ?? this.path,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerConfig &&
        other.host == host &&
        other.port == port &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(host, port, path);

  @override
  String toString() => 'ServerConfig($host:$port$path)';
}

/// Peer session information.
class PeerSession {
  /// Creates peer session info.
  const PeerSession({
    required this.peerUsername,
    required this.hasSession,
    this.messageCount = 0,
    this.lastMessageAt,
  });

  /// The peer's username.
  final String peerUsername;

  /// Whether a session is established.
  final bool hasSession;

  /// Number of messages exchanged.
  final int messageCount;

  /// Timestamp of last message.
  final DateTime? lastMessageAt;

  /// Create a copy with updated fields.
  PeerSession copyWith({
    String? peerUsername,
    bool? hasSession,
    int? messageCount,
    DateTime? lastMessageAt,
  }) =>
      PeerSession(
        peerUsername: peerUsername ?? this.peerUsername,
        hasSession: hasSession ?? this.hasSession,
        messageCount: messageCount ?? this.messageCount,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      );
}

/// Immutable engine state.
///
/// Contains all state needed by the CrypticEngine, including:
/// - Initialization and connection status
/// - User identity
/// - Active sessions
/// - Registered users list
/// - Error information
class EngineState {
  /// Creates an engine state.
  const EngineState({
    this.status = EngineStatus.uninitialized,
    this.connectionStatus = ConnectionStatus.disconnected,
    this.identity,
    this.serverConfig,
    this.sessions = const {},
    this.users = const [],
    this.error,
    this.keysUploaded = false,
    this.lastConnectedAt,
    this.reconnectAttempts = 0,
  });

  /// Initial state.
  static const initial = EngineState();

  /// Engine initialization status.
  final EngineStatus status;

  /// Connection status.
  final ConnectionStatus connectionStatus;

  /// Current user identity (null if not initialized).
  final UserIdentity? identity;

  /// Server configuration.
  final ServerConfig? serverConfig;

  /// Active sessions by peer username.
  final Map<String, PeerSession> sessions;

  /// List of registered usernames.
  final List<String> users;

  /// Last error (if any).
  final String? error;

  /// Whether identity keys have been uploaded to server.
  final bool keysUploaded;

  /// Last time connected to server.
  final DateTime? lastConnectedAt;

  /// Number of reconnection attempts.
  final int reconnectAttempts;

  // ─────────────────────────────────────────────────────────────────────────
  // Computed Properties
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether the engine is ready.
  bool get isReady => status == EngineStatus.ready;

  /// Whether the engine is connected.
  bool get isConnected => connectionStatus == ConnectionStatus.connected;

  /// Whether the engine needs initial setup.
  bool get needsSetup => status == EngineStatus.needsSetup;

  /// The username if identity is loaded.
  String? get username => identity?.username;

  /// Number of active sessions.
  int get sessionCount => sessions.length;

  /// Whether there's an error.
  bool get hasError => error != null;

  // ─────────────────────────────────────────────────────────────────────────
  // Copy Methods
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a copy with updated fields.
  EngineState copyWith({
    EngineStatus? status,
    ConnectionStatus? connectionStatus,
    UserIdentity? identity,
    ServerConfig? serverConfig,
    Map<String, PeerSession>? sessions,
    List<String>? users,
    String? error,
    bool clearError = false,
    bool? keysUploaded,
    DateTime? lastConnectedAt,
    int? reconnectAttempts,
  }) =>
      EngineState(
        status: status ?? this.status,
        connectionStatus: connectionStatus ?? this.connectionStatus,
        identity: identity ?? this.identity,
        serverConfig: serverConfig ?? this.serverConfig,
        sessions: sessions ?? this.sessions,
        users: users ?? this.users,
        error: clearError ? null : (error ?? this.error),
        keysUploaded: keysUploaded ?? this.keysUploaded,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      );

  /// Copy with a session added or updated.
  EngineState withSession(PeerSession session) => copyWith(
        sessions: {...sessions, session.peerUsername: session},
      );

  /// Copy with a session removed.
  EngineState withoutSession(String peerUsername) {
    final newSessions = Map<String, PeerSession>.from(sessions);
    newSessions.remove(peerUsername);
    return copyWith(sessions: newSessions);
  }

  /// Copy with error set.
  EngineState withError(String errorMessage) => copyWith(
        error: errorMessage,
        status: EngineStatus.failed,
      );

  /// Copy with error cleared.
  EngineState clearingError() => copyWith(clearError: true);

  @override
  String toString() => 'EngineState('
      'status: $status, '
      'connection: $connectionStatus, '
      'user: ${identity?.username}, '
      'sessions: ${sessions.length}'
      ')';
}

/// Engine event types for state changes.
sealed class EngineEvent {}

/// Engine status changed.
class EngineStatusChanged extends EngineEvent {
  /// Creates an engine status changed event.
  EngineStatusChanged(this.status, [this.error]);

  /// The new status.
  final EngineStatus status;

  /// Error if status is failed.
  final String? error;
}

/// Connection status changed.
class ConnectionStatusChanged extends EngineEvent {
  /// Creates a connection status changed event.
  ConnectionStatusChanged(this.status, [this.error]);

  /// The new connection status.
  final ConnectionStatus status;

  /// Error if status is error.
  final String? error;
}

/// Session established or updated.
class SessionUpdated extends EngineEvent {
  /// Creates a session updated event.
  SessionUpdated(this.session);

  /// The session that was updated.
  final PeerSession session;
}

/// Message received.
class MessageReceived extends EngineEvent {
  /// Creates a message received event.
  MessageReceived({
    required this.fromUser,
    required this.plaintext,
    required this.timestamp,
  });

  /// Sender username.
  final String fromUser;

  /// Decrypted message.
  final String plaintext;

  /// Message timestamp.
  final DateTime timestamp;
}

/// Message sent confirmation.
class MessageSent extends EngineEvent {
  /// Creates a message sent event.
  MessageSent({
    required this.messageId,
    required this.toUser,
    required this.timestamp,
  });

  /// The message ID.
  final String messageId;

  /// Recipient username.
  final String toUser;

  /// When the server received it.
  final DateTime timestamp;
}

/// Users list received.
class UsersListReceived extends EngineEvent {
  /// Creates a users list event.
  UsersListReceived(this.users);

  /// List of usernames.
  final List<String> users;
}

/// User status changed (online/offline).
class UserStatusChanged extends EngineEvent {
  /// Creates a user status event.
  UserStatusChanged(this.username, this.isOnline);

  /// The username.
  final String username;

  /// Whether the user is online.
  final bool isOnline;
}

/// Engine error occurred.
class EngineError extends EngineEvent {
  /// Creates an engine error event.
  EngineError(this.message, [this.cause]);

  /// Error message.
  final String message;

  /// Underlying cause.
  final Object? cause;
}

/// Informational engine message.
class EngineInfo extends EngineEvent {
  /// Creates an engine info event.
  EngineInfo(this.message);

  /// Info message.
  final String message;
}
