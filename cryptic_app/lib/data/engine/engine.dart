/// Engine module - orchestrates crypto, storage, and network layers.
///
/// This module provides the core CrypticEngine service that ties together:
/// - Cryptographic operations (X3DH, Double Ratchet)
/// - Local storage (keys, sessions, messages)
/// - Network communication (WebSocket client)
///
/// ## Usage
///
/// ```dart
/// import 'package:cryptic_app/data/engine/engine.dart';
///
/// final engine = CrypticEngine(
///   username: 'alice',
///   serverConfig: ServerConfig(host: 'example.com', port: 8443),
///   keyRepository: keyRepository,
///   sessionRepository: sessionRepository,
///   webSocketClient: webSocketClient,
/// );
///
/// await engine.initialize();
/// await engine.connect();
/// await engine.sendMessage('bob', 'Hello!');
/// ```
library;

export 'cryptic_engine.dart';
export 'engine_state.dart';
export 'message_processor.dart';
export 'session_manager.dart';
