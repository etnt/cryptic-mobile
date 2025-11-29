/// Cryptic Engine - Main orchestrator for end-to-end encrypted messaging.
///
/// Integrates crypto primitives, storage, and network layers into a
/// unified interface for secure messaging operations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../crypto/keys/key_bundle.dart';
import '../crypto/keys/key_generator.dart';
import '../crypto/ratchet/double_ratchet.dart';
import '../crypto/x3dh/x3dh_engine.dart';
import '../network/protocol/client_messages.dart' as protocol;
import '../network/protocol/protocol_codec.dart';
import '../network/protocol/server_messages.dart';
import '../network/websocket/websocket_client.dart';
import '../storage/repositories/key_repository.dart';
import '../storage/repositories/session_repository.dart';
import 'engine_state.dart';
import 'message_processor.dart';
import 'session_manager.dart';

/// CrypticEngine - Central orchestrator for the cryptic messaging system.
///
/// Responsibilities:
/// - Manages WebSocket connection lifecycle
/// - Orchestrates X3DH key agreement for new sessions
/// - Delegates message encryption/decryption to SessionManager
/// - Routes incoming messages through MessageProcessor
/// - Maintains engine state and emits events to UI
///
/// Usage:
/// ```dart
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
///
/// engine.events.listen((event) {
///   // Handle events
/// });
///
/// await engine.sendMessage('bob', 'Hello!');
/// ```
class CrypticEngine {
  /// Creates a CrypticEngine.
  CrypticEngine({
    required String username,
    required ServerConfig serverConfig,
    required KeyRepository keyRepository,
    required SessionRepository sessionRepository,
    required WebSocketClient webSocketClient,
    KeyGenerator? keyGenerator,
    X3dhEngine? x3dhEngine,
    DoubleRatchet? doubleRatchet,
  })  : _username = username,
        _keyRepository = keyRepository,
        _webSocketClient = webSocketClient,
        _keyGenerator = keyGenerator ?? KeyGenerator(),
        _x3dhEngine = x3dhEngine ?? X3dhEngine(),
        _state = EngineState(
          serverConfig: serverConfig,
        ) {
    // Initialize session manager
    _sessionManager = SessionManager(
      sessionRepository: sessionRepository,
      doubleRatchet: doubleRatchet,
    );

    // Initialize message processor
    _messageProcessor = MessageProcessor(
      sessionManager: _sessionManager,
      keyRepository: _keyRepository,
      x3dhEngine: _x3dhEngine,
    );

    // Wire up internal event handling
    _setupInternalListeners();
  }

  final String _username;
  final KeyRepository _keyRepository;
  final WebSocketClient _webSocketClient;
  final KeyGenerator _keyGenerator;
  final X3dhEngine _x3dhEngine;

  late final SessionManager _sessionManager;
  late final MessageProcessor _messageProcessor;

  EngineState _state;
  bool _isInitialized = false;
  bool _isDisposed = false;

  // Pending X3DH key bundles received from server
  final Map<String, KeyBundle> _pendingKeyBundles = {};

  // Pending messages waiting for X3DH completion
  final Map<String, List<String>> _pendingMessages = {};

  // Stream subscriptions
  StreamSubscription<ServerMessage>? _messageSubscription;
  StreamSubscription<WebSocketEvent>? _connectionSubscription;

  final _eventController = StreamController<EngineEvent>.broadcast();
  final _stateController = StreamController<EngineState>.broadcast();

  /// Current engine state.
  EngineState get state => _state;

  /// Stream of engine events.
  Stream<EngineEvent> get events => _eventController.stream;

  /// Stream of state changes.
  Stream<EngineState> get stateChanges => _stateController.stream;

  /// Whether the engine is initialized.
  bool get isInitialized => _isInitialized;

  /// Whether the engine is connected.
  bool get isConnected =>
      _state.connectionStatus == ConnectionStatus.connected;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Initialize the engine.
  ///
  /// Loads identity keys and sessions from storage.
  /// Creates new identity keys if none exist.
  Future<void> initialize() async {
    if (_isDisposed) {
      throw StateError('CrypticEngine has been disposed');
    }

    if (_isInitialized) return;

    _updateState(_state.copyWith(status: EngineStatus.initializing));

    try {
      // Check if we have identity keys
      final hasKeys = await _keyRepository.hasIdentityKeys();

      if (!hasKeys) {
        // Generate new identity keys
        await _generateIdentityKeys();
      }

      // Initialize session manager
      await _sessionManager.initialize(_username);

      // Load existing sessions
      await _sessionManager.loadAllSessions();

      _isInitialized = true;
      _updateState(_state.copyWith(status: EngineStatus.ready));
      _emitEvent(EngineStatusChanged(EngineStatus.ready));
    } catch (e) {
      _updateState(_state.withError('Initialization failed: $e'));
      _emitEvent(EngineError('Initialization failed: $e'));
      rethrow;
    }
  }

  /// Connect to the server.
  Future<void> connect() async {
    if (!_isInitialized) {
      throw StateError('CrypticEngine not initialized');
    }

    _updateState(_state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
    ));
    _emitEvent(ConnectionStatusChanged(ConnectionStatus.connecting));

    try {
      await _webSocketClient.connect();

      // Upload identity keys after connecting
      await _uploadIdentityKeys();

      // Request user list
      await requestUserList();
    } catch (e) {
      _updateState(_state.withError('Connection failed: $e'));
      _emitEvent(EngineError('Connection failed: $e'));
      rethrow;
    }
  }

  /// Disconnect from the server.
  Future<void> disconnect() async {
    await _webSocketClient.disconnect();
    _updateState(_state.copyWith(
      connectionStatus: ConnectionStatus.disconnected,
    ));
    _emitEvent(ConnectionStatusChanged(ConnectionStatus.disconnected));
  }

  /// Dispose the engine and release resources.
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;

    await _messageSubscription?.cancel();
    await _connectionSubscription?.cancel();

    _messageProcessor.dispose();
    _sessionManager.dispose();

    await _webSocketClient.disconnect();

    await _eventController.close();
    await _stateController.close();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Messaging
  // ─────────────────────────────────────────────────────────────────────────

  /// Send a message to a peer.
  ///
  /// If no session exists, initiates X3DH key agreement first.
  Future<void> sendMessage(String toUser, String plaintext) async {
    if (!_isInitialized) {
      throw StateError('CrypticEngine not initialized');
    }

    if (!isConnected) {
      throw StateError('Not connected to server');
    }

    if (_sessionManager.hasSession(toUser)) {
      // Have session - encrypt and send with Double Ratchet
      await _sendRatchetMessage(toUser, plaintext);
    } else {
      // No session - need to initiate X3DH
      await _initiateX3dh(toUser, plaintext);
    }
  }

  /// Request the list of registered users.
  Future<void> requestUserList() async {
    if (!isConnected) return;

    final message = protocol.ListUsersMessage();
    _webSocketClient.send(message);
  }

  /// Request a key bundle for a user.
  Future<void> requestKeyBundle(String username) async {
    if (!isConnected) return;

    final message = protocol.GetKeyBundleMessage(username: username);
    _webSocketClient.send(message);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal Setup
  // ─────────────────────────────────────────────────────────────────────────

  void _setupInternalListeners() {
    // Listen to WebSocket messages
    _messageSubscription = _webSocketClient.messages.listen(
      _handleServerMessage,
      onError: _handleWebSocketError,
    );

    // Listen to connection state changes
    _connectionSubscription = _webSocketClient.events.listen(
      _handleWebSocketEvent,
    );

    // Forward message processor events
    _messageProcessor.events.listen(_emitEvent);
  }

  void _handleWebSocketEvent(WebSocketEvent event) {
    if (event is ConnectionStateEvent) {
      final status = switch (event.state) {
        ConnectionState.disconnected => ConnectionStatus.disconnected,
        ConnectionState.connecting => ConnectionStatus.connecting,
        ConnectionState.connected => ConnectionStatus.connected,
        ConnectionState.error => ConnectionStatus.error,
      };

      _updateState(_state.copyWith(connectionStatus: status));
      _emitEvent(ConnectionStatusChanged(status));
    }
  }

  void _handleWebSocketError(Object error) {
    _updateState(_state.withError(error.toString()));
    _emitEvent(EngineError(error.toString()));
  }

  Future<void> _handleServerMessage(ServerMessage message) async {
    // Handle key bundle specially for X3DH initiation
    if (message is KeyBundleMessage) {
      await _handleKeyBundleReceived(message);
      return;
    }

    // Delegate other messages to processor
    final result = await _messageProcessor.processMessage(message);

    // Handle session updates from X3DH messages
    if (result is ProcessingSuccess && message is IncomingMessage) {
      if (message.isX3dh) {
        final x3dh = message.asX3dh();
        if (x3dh != null) {
          _updateState(
            _state.withSession(
              PeerSession(
                peerUsername: x3dh.fromUser,
                hasSession: true,
                messageCount: 1,
                lastMessageAt: DateTime.now(),
              ),
            ),
          );
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Key Management
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _generateIdentityKeys() async {
    // Generate full key bundle
    final keyBundle = await _keyGenerator.generateFullKeyBundle();

    // Save identity keys
    await _keyRepository.saveIdentityKeys(keyBundle.identity);

    // Save signed prekey
    await _keyRepository.saveSignedPrekey(keyBundle.signedPrekey);

    // Save one-time prekeys
    final otpkList = keyBundle.oneTimePrekeys.values.toList();
    await _keyRepository.saveOneTimePrekeys(otpkList);
  }

  Future<void> _uploadIdentityKeys() async {
    final identityKeys = await _keyRepository.loadIdentityKeys();
    if (identityKeys == null) return;

    final signedPrekey = await _keyRepository.loadSignedPrekey();
    if (signedPrekey == null) return;

    final message = protocol.UploadIdentityKeysMessage.fromKeys(
      username: _username,
      identitySignPublic: identityKeys.signPublicKey,
      identityDhPublic: identityKeys.dhPublicKey,
      signedPrekeyPublic: signedPrekey.publicKey,
      signedPrekeySignature: signedPrekey.signature,
      signedPrekeyId: signedPrekey.keyId,
    );

    _webSocketClient.send(message);

    // Upload one-time prekeys
    await _uploadOneTimePrekeys();
  }

  Future<void> _uploadOneTimePrekeys() async {
    final prekeys = await _keyRepository.loadOneTimePrekeys();
    if (prekeys.isEmpty) return;

    // Convert crypto OneTimePrekey to protocol OneTimePrekey
    final protocolPrekeys = prekeys.map((pk) => protocol.OneTimePrekey.fromBytes(
      keyId: pk.keyId,
      publicKey: pk.publicKey,
    )).toList();

    final message = protocol.UploadPrekeyBundleMessage(
      username: _username,
      oneTimePrekeys: protocolPrekeys,
    );

    _webSocketClient.send(message);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // X3DH Key Agreement
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initiateX3dh(String toUser, String plaintext) async {
    // Check if we already have a pending key bundle
    if (_pendingKeyBundles.containsKey(toUser)) {
      await _performX3dhWithBundle(toUser, plaintext);
      return;
    }

    // Queue the message and request key bundle
    _pendingMessages.putIfAbsent(toUser, () => []);
    _pendingMessages[toUser]!.add(plaintext);

    await requestKeyBundle(toUser);
  }

  Future<void> _handleKeyBundleReceived(KeyBundleMessage message) async {
    // Convert KeyBundleMessage to the Map format expected by KeyBundle
    final bundleMap = <String, dynamic>{
      'username': message.username,
      'identity_sign_key': message.identitySignKey,
      'identity_dh_key': message.identityDhKey,
      'signed_prekey': {
        'key_id': message.signedPrekey.keyId,
        'public_key': message.signedPrekey.publicKey,
        'signature': message.signedPrekey.signature,
      },
      if (message.oneTimePrekey != null)
        'one_time_prekey': {
          'key_id': message.oneTimePrekey!.keyId,
          'public_key': message.oneTimePrekey!.publicKey,
        },
    };
    final bundle = KeyBundle.fromServerResponse(bundleMap);
    _pendingKeyBundles[message.username] = bundle;

    // Check for pending messages
    final pendingMsgs = _pendingMessages.remove(message.username);
    if (pendingMsgs != null && pendingMsgs.isNotEmpty) {
      // Send first pending message with X3DH
      await _performX3dhWithBundle(message.username, pendingMsgs.first);

      // Send remaining messages with ratchet
      for (var i = 1; i < pendingMsgs.length; i++) {
        await _sendRatchetMessage(message.username, pendingMsgs[i]);
      }
    }
  }

  Future<void> _performX3dhWithBundle(String toUser, String plaintext) async {
    final bundle = _pendingKeyBundles.remove(toUser);
    if (bundle == null) {
      throw StateError('No key bundle for $toUser');
    }

    // Load our key bundle
    final ourKeys = await _keyRepository.loadOwnKeyBundle();
    if (ourKeys == null) {
      throw StateError('No identity keys available');
    }

    // Perform X3DH as sender
    final x3dhResult = await _x3dhEngine.senderInit(
      senderKeys: ourKeys,
      recipientBundle: bundle,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
    );

    // Create Double Ratchet session
    await _sessionManager.createSessionAsInitiator(
      peerUsername: toUser,
      sharedSecret: x3dhResult.sessionKey,
      ourDhKeyPair: (
        x3dhResult.ephemeralKeyPair.publicKey,
        x3dhResult.ephemeralKeyPair.privateKey,
      ),
    );

    // Build and send X3DH message
    final x3dhMessage = protocol.X3dhMessage(
      messageId: _generateMessageId(),
      fromUser: _username,
      toUser: toUser,
      identityKey: base64Encode(ourKeys.identity.dhPublicKey),
      ephemeralKey: base64Encode(x3dhResult.ephemeralKeyPair.publicKey),
      usedOneTimePrekeyId: bundle.oneTimePrekey?.keyId,
      ciphertext: base64Encode(x3dhResult.messageBlob.ciphertext),
    );

    _webSocketClient.send(x3dhMessage);

    // Update state with new session
    _updateState(
      _state.withSession(
        PeerSession(
          peerUsername: toUser,
          hasSession: true,
          messageCount: 1,
          lastMessageAt: DateTime.now(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Double Ratchet Messaging
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _sendRatchetMessage(String toUser, String plaintext) async {
    // Encrypt with Double Ratchet
    final ratchetMsg = await _sessionManager.encryptMessage(
      peerUsername: toUser,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
    );

    // Build and send ratchet message using protocol message class
    final message = protocol.RatchetMessage.fromBytes(
      messageId: _generateMessageId(),
      fromUser: _username,
      toUser: toUser,
      dhPublic: ratchetMsg.dhPublic,
      previousChainLength: ratchetMsg.prevChainLength,
      messageNumber: ratchetMsg.messageNumber,
      ciphertext: ratchetMsg.ciphertext,
    );

    _webSocketClient.send(message);

    // Update session state
    final sessionInfo = _sessionManager.getSessionInfo(toUser);
    if (sessionInfo != null) {
      _updateState(
        _state.withSession(
          sessionInfo.copyWith(lastMessageAt: DateTime.now()),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _updateState(EngineState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _emitEvent(EngineEvent event) {
    _eventController.add(event);
  }

  String _generateMessageId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = DateTime.now().hashCode;
    return '$_username-$timestamp-$random';
  }
}
