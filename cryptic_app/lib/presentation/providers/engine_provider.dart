/// Riverpod providers for the Cryptic Engine.
///
/// Provides dependency injection and state management for the engine layer.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/engine/cryptic_engine.dart';
import '../../data/engine/engine_state.dart';
import '../../data/network/websocket/websocket_client.dart';
import '../../data/storage/repositories/key_repository.dart';
import '../../data/storage/repositories/session_repository.dart';

/// Provider for the WebSocket client.
///
/// Override this in tests or when configuring for different servers.
final webSocketClientProvider = Provider<WebSocketClient>((ref) {
  throw UnimplementedError(
    'webSocketClientProvider must be overridden with a configured WebSocketClient',
  );
});

/// Provider for the key repository.
///
/// Override this in tests or when using different storage backends.
final keyRepositoryProvider = Provider<KeyRepository>((ref) {
  throw UnimplementedError(
    'keyRepositoryProvider must be overridden with a configured KeyRepository',
  );
});

/// Provider for the session repository.
///
/// Override this in tests or when using different storage backends.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  throw UnimplementedError(
    'sessionRepositoryProvider must be overridden with a configured SessionRepository',
  );
});

/// Provider for the server configuration.
final serverConfigProvider = Provider<ServerConfig>((ref) {
  // Default development configuration
  return const ServerConfig(
    host: 'localhost',
    port: 8443,
  );
});

/// Provider for the current username.
///
/// Must be set before the engine can be used.
final usernameProvider = StateProvider<String?>((ref) => null);

/// Provider for the CrypticEngine.
///
/// Creates and manages the engine lifecycle.
final engineProvider = Provider<CrypticEngine?>((ref) {
  final username = ref.watch(usernameProvider);
  if (username == null) return null;

  final serverConfig = ref.watch(serverConfigProvider);
  final keyRepository = ref.watch(keyRepositoryProvider);
  final sessionRepository = ref.watch(sessionRepositoryProvider);
  final webSocketClient = ref.watch(webSocketClientProvider);

  final engine = CrypticEngine(
    username: username,
    serverConfig: serverConfig,
    keyRepository: keyRepository,
    sessionRepository: sessionRepository,
    webSocketClient: webSocketClient,
  );

  ref.onDispose(() {
    engine.dispose();
  });

  return engine;
});

/// Provider for the engine state.
///
/// Provides reactive access to the current engine state.
final engineStateProvider = StreamProvider<EngineState>((ref) {
  final engine = ref.watch(engineProvider);
  if (engine == null) {
    return Stream.value(const EngineState());
  }
  return engine.stateChanges;
});

/// Provider for the engine's current state (non-stream).
final currentEngineStateProvider = Provider<EngineState>((ref) {
  final engine = ref.watch(engineProvider);
  return engine?.state ?? const EngineState();
});

/// Provider for engine events.
///
/// Provides reactive access to engine events.
final engineEventsProvider = StreamProvider<EngineEvent>((ref) {
  final engine = ref.watch(engineProvider);
  if (engine == null) {
    return const Stream.empty();
  }
  return engine.events;
});

/// Provider for connection status.
final connectionStatusProvider = Provider<ConnectionStatus>((ref) {
  final state = ref.watch(currentEngineStateProvider);
  return state.connectionStatus;
});

/// Provider for whether the engine is connected.
final isConnectedProvider = Provider<bool>((ref) {
  final status = ref.watch(connectionStatusProvider);
  return status == ConnectionStatus.connected;
});

/// Provider for engine initialization status.
final engineStatusProvider = Provider<EngineStatus>((ref) {
  final state = ref.watch(currentEngineStateProvider);
  return state.status;
});

/// Provider for the list of registered users.
final usersProvider = Provider<List<String>>((ref) {
  final state = ref.watch(currentEngineStateProvider);
  return state.users;
});

/// Provider for active sessions.
final sessionsProvider = Provider<Map<String, PeerSession>>((ref) {
  final state = ref.watch(currentEngineStateProvider);
  return state.sessions;
});

/// Provider for checking if a session exists with a peer.
final hasSessionProvider = Provider.family<bool, String>((ref, peerUsername) {
  final sessions = ref.watch(sessionsProvider);
  return sessions.containsKey(peerUsername);
});
