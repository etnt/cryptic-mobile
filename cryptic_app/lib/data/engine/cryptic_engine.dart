/// Cryptic Engine - Main orchestrator for end-to-end encrypted messaging.
///
/// Integrates crypto primitives, storage, and network layers into a
/// unified interface for secure messaging operations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../core/utils/logger.dart';
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

  // Reconnection state
  bool _intentionalDisconnect = false;
  Timer? _reconnectTimer;
  Timer? _keepaliveTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 60);
  static const Duration _keepaliveInterval = Duration(seconds: 30);

  // Message processing serialization – ensures only one message is
  // processed at a time so Double Ratchet state stays consistent.
  Future<void> _messageProcessingChain = Future.value();

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

    _intentionalDisconnect = false;
    _reconnectAttempts = 0;

    _updateState(_state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
    ),);
    _emitEvent(ConnectionStatusChanged(ConnectionStatus.connecting));

    try {
      await _webSocketClient.connect();

      // Upload identity keys after connecting
      await _uploadIdentityKeys();

      // Request pending messages that arrived while offline
      _webSocketClient.send(protocol.RequestPendingMessagesMessage());

      // Request user list
      await requestUserList();

      // Start keepalive to prevent server idle timeout
      _startKeepalive();
    } catch (e) {
      _updateState(_state.withError('Connection failed: $e'));
      _emitEvent(EngineError('Connection failed: $e'));
      rethrow;
    }
  }

  /// Disconnect from the server.
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _keepaliveTimer?.cancel();
    await _webSocketClient.disconnect();
    _updateState(_state.copyWith(
      connectionStatus: ConnectionStatus.disconnected,
    ),);
    _emitEvent(ConnectionStatusChanged(ConnectionStatus.disconnected));
  }

  /// Dispose the engine and release resources.
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _keepaliveTimer?.cancel();

    await _messageSubscription?.cancel();
    await _connectionSubscription?.cancel();

    _messageProcessor.dispose();
    await _sessionManager.dispose();

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
    print('[Engine] sendMessage called: to=$toUser, plaintext=$plaintext');
    
    if (!_isInitialized) {
      print('[Engine] sendMessage: Not initialized!');
      throw StateError('CrypticEngine not initialized');
    }

    if (!isConnected) {
      print('[Engine] sendMessage: Not connected!');
      throw StateError('Not connected to server');
    }

    if (_sessionManager.hasSession(toUser)) {
      final diag = _sessionManager.getSessionDiagnostics(toUser);
      print('[Engine] sendMessage: Have session for $toUser $diag');
      // Have session - encrypt and send with Double Ratchet
      await _sendRatchetMessage(toUser, plaintext);
    } else {
      print('[Engine] sendMessage: No session for $toUser '
          '(loaded peers: ${_sessionManager.peerUsernames}), initiating X3DH');
      // No session - need to initiate X3DH
      await _initiateX3dh(toUser, plaintext);
    }
  }

  /// Request the list of online users.
  Future<void> requestUserList() async {
    print('[Engine] requestUserList called, isConnected=$isConnected');
    if (!isConnected) {
      print('[Engine] requestUserList: Not connected, skipping');
      return;
    }

    final message = protocol.OnlineUsersMessage();
    _webSocketClient.send(message);
    print('[Engine] requestUserList: Sent online_users message');
  }

  /// Request the list of all registered users (admin only).
  Future<void> requestAllUsers() async {
    if (!isConnected) return;

    final message = protocol.ListUsersMessage();
    _webSocketClient.send(message);
  }

  /// Request a key bundle for a user.
  Future<void> requestKeyBundle(String username) async {
    print('[Engine] requestKeyBundle: username=$username, isConnected=$isConnected');
    if (!isConnected) {
      print('[Engine] requestKeyBundle: Not connected, skipping');
      return;
    }

    final message = protocol.GetKeyBundleMessage(username: username);
    print('[Engine] requestKeyBundle: Sending get_key_bundle message');
    _webSocketClient.send(message);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session Management (Debug)
  // ─────────────────────────────────────────────────────────────────────────

  /// Clear a session with a specific peer.
  ///
  /// This forces a new X3DH exchange on the next message.
  /// Useful for debugging or recovering from stale session state.
  Future<void> clearSession(String peerUsername) async {
    final hadSession = _sessionManager.hasSession(peerUsername);
    print('[Engine] clearSession: Clearing session with $peerUsername (had session: $hadSession)');
    await _sessionManager.deleteSession(peerUsername);
    final stillHasSession = _sessionManager.hasSession(peerUsername);
    print('[Engine] clearSession: After delete, hasSession=$stillHasSession');
    _emitEvent(EngineInfo('Session with $peerUsername cleared'));
  }

  /// Clear all sessions.
  ///
  /// This forces new X3DH exchanges with all peers.
  /// Useful for debugging or recovering from corrupted state.
  Future<void> clearAllSessions() async {
    final peers = _sessionManager.peerUsernames;
    print('[Engine] clearAllSessions: Clearing ${peers.length} sessions');
    await _sessionManager.deleteAllSessions();
    _emitEvent(EngineInfo('All sessions cleared (${peers.length} peers)'));
  }

  /// Check if a session exists with a peer.
  bool hasSession(String peerUsername) => _sessionManager.hasSession(peerUsername);

  /// Get list of peers with active sessions.
  List<String> get sessionPeers => _sessionManager.peerUsernames;

  /// Get diagnostic info for a single peer session.
  Map<String, dynamic>? getSessionDiagnostics(String peerUsername) =>
      _sessionManager.getSessionDiagnostics(peerUsername);

  /// Get diagnostics for all sessions.
  Map<String, Map<String, dynamic>> getAllSessionDiagnostics() =>
      _sessionManager.getAllSessionDiagnostics();

  // ─────────────────────────────────────────────────────────────────────────
  // Internal Setup
  // ─────────────────────────────────────────────────────────────────────────

  void _setupInternalListeners() {
    // Listen to WebSocket messages – serialized so Double Ratchet state
    // is never accessed concurrently by two messages.
    _messageSubscription = _webSocketClient.messages.listen(
      _enqueueServerMessage,
      onError: _handleWebSocketError,
    );

    // Listen to connection state changes
    _connectionSubscription = _webSocketClient.events.listen(
      _handleWebSocketEvent,
    );

    // Forward message processor events and handle state updates
    _messageProcessor.events.listen((event) {
      _emitEvent(event);
      _handleProcessorEvent(event);
    });
  }

  void _handleProcessorEvent(EngineEvent event) {
    if (event is UsersListReceived) {
      print('[Engine] Updating state with users: ${event.users}');
      _updateState(_state.copyWith(users: event.users));
    } else if (event is UserStatusChanged) {
      print('[Engine] User status: ${event.username} online=${event.isOnline}');
      final users = List<String>.from(_state.users);
      if (event.isOnline && !users.contains(event.username)) {
        users.add(event.username);
      } else if (!event.isOnline) {
        users.remove(event.username);
      }
      _updateState(_state.copyWith(users: users));
    }
  }

  void _handleWebSocketEvent(WebSocketEvent event) {
    if (event is ConnectionStateEvent) {
      final status = switch (event.state) {
        ConnectionState.disconnected => ConnectionStatus.disconnected,
        ConnectionState.connecting => ConnectionStatus.connecting,
        ConnectionState.connected => ConnectionStatus.connected,
        ConnectionState.error => ConnectionStatus.error,
      };

      print('[Engine] Connection status changed: $status');
      AppLogger.info('Engine: Connection status changed to $status', tag: 'Engine');
      _updateState(_state.copyWith(connectionStatus: status));
      _emitEvent(ConnectionStatusChanged(status));

      // Auto-reconnect on unexpected disconnect
      if (status == ConnectionStatus.disconnected &&
          !_intentionalDisconnect &&
          !_isDisposed &&
          _isInitialized) {
        _keepaliveTimer?.cancel();
        _scheduleReconnect();
      }

      // Reset reconnect counter on successful connection
      if (status == ConnectionStatus.connected) {
        _reconnectAttempts = 0;
      }
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('[Engine] Max reconnect attempts ($_maxReconnectAttempts) reached, giving up');
      _emitEvent(EngineError('Connection lost after $_maxReconnectAttempts reconnect attempts'));
      return;
    }

    _reconnectAttempts++;
    final delay = _calculateBackoff();
    print('[Engine] Scheduling reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_isDisposed || _intentionalDisconnect) return;
      print('[Engine] Attempting reconnect #$_reconnectAttempts');
      try {
        await connect();
      } catch (e) {
        print('[Engine] Reconnect attempt $_reconnectAttempts failed: $e');
        // _handleWebSocketEvent will trigger another _scheduleReconnect
      }
    });
  }

  Duration _calculateBackoff() {
    final baseMs = _initialReconnectDelay.inMilliseconds;
    final multiplier = pow(2, _reconnectAttempts - 1);
    final delayMs = (baseMs * multiplier).round();
    final maxMs = _maxReconnectDelay.inMilliseconds;
    // Add ±10% jitter
    final jitter = (delayMs * 0.1 * (Random().nextDouble() * 2 - 1)).round();
    return Duration(milliseconds: min(delayMs + jitter, maxMs));
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(_keepaliveInterval, (_) {
      if (isConnected) {
        try {
          // Use online_users as keepalive — server recognizes it and
          // it keeps the connection alive without a dedicated ping command.
          _webSocketClient.sendRaw('{"type":"online_users"}');
        } catch (_) {
          // Connection error will be handled by _onDone/_onError
        }
      }
    });
  }

  void _handleWebSocketError(Object error) {
    _updateState(_state.withError(error.toString()));
    _emitEvent(EngineError(error.toString()));
  }

  /// Enqueue a server message for serial processing.
  ///
  /// Each message is chained onto [_messageProcessingChain] so that
  /// the previous handler completes before the next one starts.
  void _enqueueServerMessage(ServerMessage message) {
    _messageProcessingChain = _messageProcessingChain.then((_) async {
      try {
        await _handleServerMessage(message);
      } catch (e, st) {
        print('[Engine] Error processing server message: $e\n$st');
      }
    });
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
    ),).toList();

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
    print('[Engine] _initiateX3dh: toUser=$toUser');
    
    // Check if we already have a pending key bundle
    if (_pendingKeyBundles.containsKey(toUser)) {
      print('[Engine] _initiateX3dh: Have pending bundle, performing X3DH');
      await _performX3dhWithBundle(toUser, plaintext);
      return;
    }

    // Queue the message and request key bundle
    print('[Engine] _initiateX3dh: No bundle, queuing message and requesting key bundle');
    _pendingMessages.putIfAbsent(toUser, () => []);
    _pendingMessages[toUser]!.add(plaintext);

    await requestKeyBundle(toUser);
  }

  Future<void> _handleKeyBundleReceived(KeyBundleMessage message) async {
    print('[Engine] _handleKeyBundleReceived: Got bundle for ${message.username}');
    print('[Engine] _handleKeyBundleReceived: identitySignKey=${message.identitySignKey.substring(0, 20)}...');
    print('[Engine] _handleKeyBundleReceived: identityDhKey=${message.identityDhKey.substring(0, 20)}...');
    print('[Engine] _handleKeyBundleReceived: signedPrekey.keyId=${message.signedPrekey.keyId}');
    print('[Engine] _handleKeyBundleReceived: oneTimePrekey=${message.oneTimePrekey != null ? "present, keyId=${message.oneTimePrekey!.keyId}" : "null"}');
    
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
    
    try {
      final bundle = KeyBundle.fromServerResponse(bundleMap);
      print('[Engine] _handleKeyBundleReceived: KeyBundle created successfully');
      _pendingKeyBundles[message.username] = bundle;

      // Check for pending messages
      print('[Engine] _handleKeyBundleReceived: Pending messages for ${message.username}: ${_pendingMessages[message.username]}');
      final pendingMsgs = _pendingMessages.remove(message.username);
      if (pendingMsgs != null && pendingMsgs.isNotEmpty) {
        print('[Engine] _handleKeyBundleReceived: Have ${pendingMsgs.length} pending messages, performing X3DH');
        // Send first pending message with X3DH
        await _performX3dhWithBundle(message.username, pendingMsgs.first);

        // Send remaining messages with ratchet
        for (var i = 1; i < pendingMsgs.length; i++) {
          await _sendRatchetMessage(message.username, pendingMsgs[i]);
        }
      } else {
        print('[Engine] _handleKeyBundleReceived: No pending messages for ${message.username}');
      }
    } catch (e, stack) {
      print('[Engine] _handleKeyBundleReceived: ERROR: $e');
      print('[Engine] _handleKeyBundleReceived: Stack: $stack');
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

    // Build and send X3DH message with all required fields
    final messageBlob = x3dhResult.messageBlob;
    final metadata = messageBlob.metadata;
    final metadataJson = jsonEncode(metadata.toMap());
    
    print('[Engine] _performX3dhWithBundle: Building X3DH message');
    print('[Engine] _performX3dhWithBundle: messageId=${base64Encode(x3dhResult.messageId)}');
    print('[Engine] _performX3dhWithBundle: fromUser=$_username, toUser=$toUser');
    print('[Engine] _performX3dhWithBundle: ephemeralPublic len=${metadata.ephemeralPublic.length}');
    print('[Engine] _performX3dhWithBundle: otpkId=${metadata.otpkId != null ? "present" : "null"}');
    print('[Engine] _performX3dhWithBundle: ciphertext len=${messageBlob.ciphertext.length}');
    print('[Engine] _performX3dhWithBundle: nonce len=${messageBlob.nonce.length}');
    print('[Engine] _performX3dhWithBundle: signature len=${messageBlob.signature.length}');
    print('[Engine] _performX3dhWithBundle: metadata=${metadataJson.substring(0, metadataJson.length.clamp(0, 100))}...');
    
    final x3dhMessage = protocol.X3dhMessage.fromMessageBlob(
      messageId: base64Encode(x3dhResult.messageId),
      fromUser: _username,
      toUser: toUser,
      ephemeralPublic: metadata.ephemeralPublic,
      otpkId: metadata.otpkId,
      ciphertext: messageBlob.ciphertext,
      nonce: messageBlob.nonce,
      signature: messageBlob.signature,
      metadataJson: metadataJson,
    );

    print('[Engine] _performX3dhWithBundle: Final JSON=${jsonEncode(x3dhMessage.toJson())}');
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
    final diag = _sessionManager.getSessionDiagnostics(toUser);
    print('[Engine] _sendRatchetMessage: toUser=$toUser, from=$_username, sessionDiag=$diag');
    
    // Encrypt with Double Ratchet
    final ratchetMsg = await _sessionManager.encryptMessage(
      peerUsername: toUser,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
    );

    // Build and send ratchet message using protocol message class
    // Server expects: from, to, message_id, dh_public, dh_step, prev_chain_length, msg_number, ciphertext, nonce
    final message = protocol.RatchetMessage.fromCryptoMessage(
      messageId: _generateMessageId(),
      fromUser: _username,
      toUser: toUser,
      dhPublic: ratchetMsg.dhPublic,
      dhStep: ratchetMsg.dhStep,
      prevChainLength: ratchetMsg.prevChainLength,
      msgNumber: ratchetMsg.messageNumber,
      ciphertext: ratchetMsg.ciphertext,
      nonce: ratchetMsg.nonce,
    );

    print('[Engine] _sendRatchetMessage: Sending ratchet to $toUser (dhStep=${ratchetMsg.dhStep}, msgNum=${ratchetMsg.messageNumber}, from=$_username)');
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
    print('[Engine] Emitting event: ${event.runtimeType}');
    _eventController.add(event);
  }

  String _generateMessageId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = DateTime.now().hashCode;
    return '$_username-$timestamp-$random';
  }
}
