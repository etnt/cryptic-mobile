/// Cryptic Engine - Main orchestrator for end-to-end encrypted messaging.
///
/// Integrates crypto primitives, storage, and network layers into a
/// unified interface for secure messaging operations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../core/utils/logger.dart';
import '../crypto/keys/key_bundle.dart';
import '../crypto/keys/key_generator.dart';
import '../crypto/ratchet/double_ratchet.dart';
import '../crypto/x3dh/x3dh_engine.dart';
import '../network/protocol/client_messages.dart' as protocol;
import '../network/protocol/protocol_codec.dart';
import '../network/protocol/server_messages.dart';
import '../network/websocket/websocket_client.dart';
import '../storage/media_store.dart';
import '../storage/repositories/key_repository.dart';
import '../storage/repositories/session_repository.dart';
import 'engine_state.dart';
import 'file_reassembler.dart';
import 'message_processor.dart';
import 'payload_codec.dart';
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

    // Initialize incoming attachment reassembly and message processing.
    _fileReassembler = FileReassembler(mediaStore: MediaStore());
    _messageProcessor = MessageProcessor(
      sessionManager: _sessionManager,
      keyRepository: _keyRepository,
      fileReassembler: _fileReassembler,
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
  late final FileReassembler _fileReassembler;

  EngineState _state;
  bool _isInitialized = false;
  bool _isDisposed = false;

  // Pending X3DH key bundles received from server
  final Map<String, KeyBundle> _pendingKeyBundles = {};

  // Pending messages waiting for X3DH completion
  final Map<String, List<_QueuedOutbound>> _pendingMessages = {};
  final Map<String, Timer> _pendingBundleTimeouts = {};
  static const Duration _keyBundleTimeout = Duration(seconds: 30);

  // Reconnection state
  bool _intentionalDisconnect = false;
  Timer? _reconnectTimer;
  bool _resumeReconnectInProgress = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 60);

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
  bool get isConnected => _state.connectionStatus == ConnectionStatus.connected;

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
  Future<void> connect({bool resetReconnectAttempts = true}) async {
    if (!_isInitialized) {
      throw StateError('CrypticEngine not initialized');
    }

    _intentionalDisconnect = false;
    if (resetReconnectAttempts) {
      _reconnectAttempts = 0;
    }

    _updateState(
      _state.copyWith(
        connectionStatus: ConnectionStatus.connecting,
      ),
    );
    _emitEvent(ConnectionStatusChanged(ConnectionStatus.connecting));

    try {
      await _webSocketClient.connect();

      // Upload identity keys after connecting
      await _uploadIdentityKeys();

      // Request pending messages that arrived while offline
      _webSocketClient.send(protocol.RequestPendingMessagesMessage());

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
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    await _webSocketClient.disconnect();
    _updateState(
      _state.copyWith(
        connectionStatus: ConnectionStatus.disconnected,
      ),
    );
    _emitEvent(ConnectionStatusChanged(ConnectionStatus.disconnected));
  }

  /// Dispose the engine and release resources.
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    for (final timer in _pendingBundleTimeouts.values) {
      timer.cancel();
    }
    _pendingBundleTimeouts.clear();
    _pendingMessages.clear();

    await _messageSubscription?.cancel();
    await _connectionSubscription?.cancel();

    _messageProcessor.dispose();
    await _sessionManager.dispose();

    await _webSocketClient.disconnect();

    await _eventController.close();
    await _stateController.close();
  }

  /// Re-establish the WebSocket after the operating system resumes the app.
  ///
  /// Mobile platforms suspend Dart timers and socket processing in the
  /// background, while the server is free to time out the old connection.
  /// Replacing the possibly stale socket guarantees that identity keys are
  /// uploaded again and pending messages are requested immediately.
  Future<void> reconnectAfterAppResume() async {
    if (_isDisposed || !_isInitialized || _resumeReconnectInProgress) return;

    _resumeReconnectInProgress = true;

    // Keep a socket that still answers. Dropping it would disrupt transfers
    // and force a needless re-upload of keys.
    if (isConnected &&
        await _webSocketClient.checkAlive(protocol.OnlineUsersMessage())) {
      AppLogger.info(
        'Engine: Connection still alive after resume, keeping it',
        tag: 'Engine',
      );
      _resumeReconnectInProgress = false;
      return;
    }

    _reconnectTimer?.cancel();
    _intentionalDisconnect = true;

    try {
      await _webSocketClient.disconnect();
      _intentionalDisconnect = false;
      await connect();
    } catch (_) {
      _intentionalDisconnect = false;
      _scheduleReconnect();
    } finally {
      _resumeReconnectInProgress = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Messaging
  // ─────────────────────────────────────────────────────────────────────────

  /// Send a message to a peer.
  ///
  /// If no session exists, initiates X3DH key agreement first.
  Future<void> sendMessage(String toUser, String plaintext) async {
    _checkCanSend();
    await _sendPayload(
      toUser,
      _QueuedOutbound(PayloadCodec.encodeText(plaintext)),
    );
  }

  /// Encrypts and sends a file in bounded independent ratchet chunks.
  Future<String> sendFile(
    String toUser,
    Uint8List bytes,
    String fileName,
    String mimeType, {
    String? fileId,
  }) async {
    // A reconnect (e.g. after the app resumed) may be in progress; wait for it.
    await waitUntilConnected();
    _checkCanSend();
    if (bytes.isEmpty || bytes.length > AttachmentLimits.maxFileBytes) {
      throw ArgumentError('File must be between 1 byte and 10 MB');
    }
    final actualFileId = fileId ?? const Uuid().v4().replaceAll('-', '');
    final chunks = PayloadCodec.splitFile(bytes);
    final total = chunks.length;
    final messages = <_QueuedOutbound>[];
    for (var index = 0; index < total; index++) {
      final payload = PayloadCodec.encodeFileChunk(
        fileId: actualFileId,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        index: index,
        totalChunks: total,
        bytes: chunks[index],
      );
      messages.add(
        _QueuedOutbound(
          payload,
          fileId: actualFileId,
          fileName: fileName,
          chunkIndex: index,
          totalChunks: total,
          toUser: toUser,
        ),
      );
    }
    await _sendPayloads(toUser, messages);
    return actualFileId;
  }

  /// Waits until the engine is connected, or [timeout] passes.
  Future<void> waitUntilConnected({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!isConnected &&
        !_isDisposed &&
        _isInitialized &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  void _checkCanSend() {
    if (!_isInitialized) throw StateError('CrypticEngine not initialized');
    if (!isConnected) throw StateError('Not connected to server');
  }

  /// Request the list of online users.
  Future<void> requestUserList() async {
    if (!isConnected) {
      return;
    }

    final message = protocol.OnlineUsersMessage();
    _webSocketClient.send(message);
  }

  /// Request the list of all registered users (admin only).
  Future<void> requestAllUsers() async {
    if (!isConnected) return;

    final message = protocol.ListUsersMessage();
    _webSocketClient.send(message);
  }

  /// Request a key bundle for a user.
  Future<void> requestKeyBundle(String username) async {
    if (!isConnected) {
      return;
    }

    final message = protocol.GetKeyBundleMessage(username: username);
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
    await _sessionManager.deleteSession(peerUsername);
    _emitEvent(EngineInfo('Session with $peerUsername cleared'));
  }

  /// Clear all sessions.
  ///
  /// This forces new X3DH exchanges with all peers.
  /// Useful for debugging or recovering from corrupted state.
  Future<void> clearAllSessions() async {
    final peers = _sessionManager.peerUsernames;
    await _sessionManager.deleteAllSessions();
    _emitEvent(EngineInfo('All sessions cleared (${peers.length} peers)'));
  }

  /// Check if a session exists with a peer.
  bool hasSession(String peerUsername) =>
      _sessionManager.hasSession(peerUsername);

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
      _updateState(_state.copyWith(users: event.users));
    } else if (event is UserStatusChanged) {
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

      AppLogger.info(
        'Engine: Connection status changed to $status',
        tag: 'Engine',
      );
      _updateState(_state.copyWith(connectionStatus: status));
      _emitEvent(ConnectionStatusChanged(status));

      // Auto-reconnect on unexpected disconnect
      if ((status == ConnectionStatus.disconnected ||
              status == ConnectionStatus.error) &&
          !_intentionalDisconnect &&
          !_isDisposed &&
          _isInitialized) {
        _scheduleReconnect();
      }

      // Reset reconnect counter on successful connection
      if (status == ConnectionStatus.connected) {
        _reconnectAttempts = 0;
      }
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      AppLogger.warning(
        'Engine: Max reconnect attempts ($_maxReconnectAttempts) reached, giving up',
        tag: 'Engine',
      );
      _emitEvent(
        EngineError(
          'Connection lost after $_maxReconnectAttempts reconnect attempts',
        ),
      );
      return;
    }

    _reconnectAttempts++;
    final delay = _calculateBackoff();
    AppLogger.info(
      'Engine: Scheduling reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delay.inSeconds}s',
      tag: 'Engine',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_isDisposed || _intentionalDisconnect) return;
      try {
        await connect(resetReconnectAttempts: false);
      } catch (e) {
        AppLogger.warning(
          'Engine: Reconnect attempt $_reconnectAttempts failed',
          tag: 'Engine',
          error: e,
        );
        // The connection error event schedules the next attempt.
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
        AppLogger.error(
          'Error processing server message',
          tag: 'Engine',
          error: e,
          stackTrace: st,
        );
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

    if (message is IncomingMessage &&
        message.messageId.isNotEmpty &&
        (result is ProcessingSuccess || result is ProcessingDuplicate)) {
      _webSocketClient.send(
        protocol.MessageAckMessage(messageId: message.messageId),
      );
    }

    // A successful X3DH decryption creates a session even when its plaintext
    // is an intermediate file chunk and therefore emits no message event.
    if (result is ProcessingSuccess &&
        message is IncomingMessage &&
        message.isX3dh) {
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
    final protocolPrekeys = prekeys
        .map(
          (pk) => protocol.OneTimePrekey.fromBytes(
            keyId: pk.keyId,
            publicKey: pk.publicKey,
          ),
        )
        .toList();

    final message = protocol.UploadPrekeyBundleMessage(
      username: _username,
      oneTimePrekeys: protocolPrekeys,
    );

    _webSocketClient.send(message);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // X3DH Key Agreement
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _sendPayload(String toUser, _QueuedOutbound outbound) =>
      _sendPayloads(toUser, [outbound]);

  Future<void> _sendPayloads(
    String toUser,
    List<_QueuedOutbound> outbound,
  ) async {
    if (_sessionManager.hasSession(toUser)) {
      try {
        for (final item in outbound) {
          await _sendRatchetBytes(toUser, item.bytes);
          _reportFileProgress(item);
        }
      } catch (_) {
        // A failed chunk can consume ratchet state, so stop this transfer and
        // do not retry its remaining chunks with the same file ID. The user
        // must restart it as a new transfer.
        _reportFileFailures(outbound);
        rethrow;
      }
      return;
    }
    final bundle = _pendingKeyBundles.remove(toUser);
    if (bundle != null) {
      try {
        await _performX3dhWithBundle(toUser, outbound.first.bytes, bundle);
        _reportFileProgress(outbound.first);
        for (final item in outbound.skip(1)) {
          await _sendRatchetBytes(toUser, item.bytes);
          _reportFileProgress(item);
        }
      } catch (_) {
        // Never resume a partially sent transfer; retrying must create a new
        // transfer ID because the ratchet may already have advanced.
        _reportFileFailures(outbound);
        rethrow;
      }
      return;
    }
    _pendingMessages.putIfAbsent(toUser, () => []).addAll(outbound);
    if (outbound.any((item) => item.fileId != null)) {
      _pendingBundleTimeouts.putIfAbsent(
        toUser,
        () => Timer(
          _keyBundleTimeout,
          () => _failPendingKeyBundle(toUser),
        ),
      );
    }
    await requestKeyBundle(toUser);
  }

  void _reportFileProgress(_QueuedOutbound outbound) {
    if (outbound.fileId == null || outbound.toUser == null) return;
    final sent = outbound.chunkIndex! + 1;
    _emitEvent(
      FileSendProgress(
        toUser: outbound.toUser!,
        fileId: outbound.fileId!,
        fileName: outbound.fileName!,
        sentChunks: sent,
        totalChunks: outbound.totalChunks!,
        progress: sent / outbound.totalChunks!,
      ),
    );
  }

  void _failPendingKeyBundle(String toUser) {
    _pendingBundleTimeouts.remove(toUser)?.cancel();
    final pending = _pendingMessages[toUser];
    if (pending == null) return;
    final files = pending.where((item) => item.fileId != null).toList();
    final retained = pending.where((item) => item.fileId == null).toList();
    if (retained.isEmpty) {
      _pendingMessages.remove(toUser);
    } else {
      _pendingMessages[toUser] = retained;
    }
    if (files.isEmpty) return;
    _reportFileFailures(files);
    _emitEvent(
      EngineError(
        'File transfer failed: no key bundle received from $toUser',
      ),
    );
  }

  void _reportFileFailures(Iterable<_QueuedOutbound> outbound) {
    final files = <String, _QueuedOutbound>{};
    for (final item in outbound) {
      if (item.fileId != null) files.putIfAbsent(item.fileId!, () => item);
    }
    for (final item in files.values) {
      _emitEvent(
        FileSendProgress(
          toUser: item.toUser!,
          fileId: item.fileId!,
          fileName: item.fileName!,
          sentChunks: 0,
          totalChunks: item.totalChunks!,
          progress: 0,
          failed: true,
        ),
      );
    }
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

    List<_QueuedOutbound>? pendingForPeer;
    var fileChunksSent = 0;
    try {
      final bundle = KeyBundle.fromServerResponse(bundleMap);

      final pendingMsgs = _pendingMessages.remove(message.username);
      pendingForPeer = pendingMsgs;
      _pendingBundleTimeouts.remove(message.username)?.cancel();
      if (pendingMsgs != null && pendingMsgs.isNotEmpty) {
        await _performX3dhWithBundle(
          message.username,
          pendingMsgs.first.bytes,
          bundle,
        );
        _reportFileProgress(pendingMsgs.first);
        if (pendingMsgs.first.fileId != null) fileChunksSent++;
        for (final outbound in pendingMsgs.skip(1)) {
          await _sendRatchetBytes(message.username, outbound.bytes);
          _reportFileProgress(outbound);
          if (outbound.fileId != null) fileChunksSent++;
        }
      } else {
        _pendingKeyBundles[message.username] = bundle;
      }
    } catch (e, stack) {
      _reportFileFailures(
        pendingForPeer ?? _pendingMessages.remove(message.username) ?? const [],
      );
      _pendingBundleTimeouts.remove(message.username)?.cancel();
      AppLogger.error(
        '[Engine] _handleKeyBundleReceived: Failed queued transfers after '
        '$fileChunksSent file chunks were sent',
        tag: 'Engine',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _performX3dhWithBundle(
    String toUser,
    Uint8List plaintext,
    KeyBundle bundle,
  ) async {
    // Load our key bundle
    final ourKeys = await _keyRepository.loadOwnKeyBundle();
    if (ourKeys == null) {
      throw StateError('No identity keys available');
    }

    // Perform X3DH as sender
    final x3dhResult = await _x3dhEngine.senderInit(
      senderKeys: ourKeys,
      recipientBundle: bundle,
      plaintext: plaintext,
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

  Future<void> _sendRatchetBytes(String toUser, Uint8List plaintext) async {
    // Encrypt with Double Ratchet
    final ratchetMsg = await _sessionManager.encryptMessage(
      peerUsername: toUser,
      plaintext: plaintext,
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

class _QueuedOutbound {
  const _QueuedOutbound(
    this.bytes, {
    this.fileId,
    this.fileName,
    this.chunkIndex,
    this.totalChunks,
    this.toUser,
  });

  final Uint8List bytes;
  final String? fileId;
  final String? fileName;
  final int? chunkIndex;
  final int? totalChunks;
  final String? toUser;
}
