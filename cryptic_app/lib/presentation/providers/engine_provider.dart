/// Riverpod providers for the Cryptic Engine.
///
/// Provides dependency injection and state management for the engine layer.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/engine/cryptic_engine.dart';
import '../../data/engine/engine_state.dart';
import '../../data/storage/repositories/key_repository.dart';
import '../../data/storage/repositories/session_repository.dart';
import 'auth_provider.dart';

/// Provider for the key repository.
///
/// Override this in tests or when using different storage backends.
final keyRepositoryProvider = Provider<KeyRepository>((ref) => KeyRepository());

/// Provider for the session repository.
///
/// Override this in tests or when using different storage backends.
final sessionRepositoryProvider =
    Provider<SessionRepository>((ref) => SessionRepository());

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
/// Derived from auth state.
final usernameProvider =
    Provider<String?>((ref) => ref.watch(currentUsernameProvider));

/// Provider for the CrypticEngine.
///
/// Uses the authenticated engine from auth_provider.
final engineProvider =
    Provider<CrypticEngine?>((ref) => ref.watch(authenticatedEngineProvider));

/// Provider for the engine state.
///
/// Provides reactive access to the current engine state.
final engineStateProvider = StreamProvider<EngineState>((ref) {
  final engine = ref.watch(engineProvider);
  if (engine == null) {
    return Stream.value(EngineState.initial);
  }
  return engine.stateChanges;
});

/// Provider for the engine's current state (non-stream).
final currentEngineStateProvider = Provider<EngineState>((ref) {
  final engine = ref.watch(engineProvider);
  return engine?.state ?? EngineState.initial;
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

/// Provider for the list of registered users (excluding current user).
final usersProvider = Provider<List<String>>((ref) {
  // Watch the stream-based state provider to get reactive updates
  final asyncState = ref.watch(engineStateProvider);
  final allUsers = asyncState.valueOrNull?.users ?? [];
  
  // Filter out the current user - can't chat with yourself
  final currentUsername = ref.watch(usernameProvider);
  if (currentUsername == null) return allUsers;
  
  return allUsers.where((user) => user != currentUsername).toList();
});

/// Provider for active sessions.
final sessionsProvider = Provider<Map<String, PeerSession>>((ref) {
  // Watch the stream-based state provider to get reactive updates
  final asyncState = ref.watch(engineStateProvider);
  return asyncState.valueOrNull?.sessions ?? {};
});

/// Provider for checking if a session exists with a peer.
final hasSessionProvider = Provider.family<bool, String>((ref, peerUsername) {
  final sessions = ref.watch(sessionsProvider);
  return sessions.containsKey(peerUsername);
});
