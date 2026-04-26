/// WebSocket client for Cryptic server communication.
///
/// Provides a low-level WebSocket connection with mTLS support,
/// message sending/receiving, and connection state management.
library;

import 'dart:async';
import 'dart:io';

import '../../../core/utils/logger.dart';
import '../protocol/protocol_codec.dart';
import '../protocol/protocol_message.dart';
import '../protocol/server_messages.dart';
import 'mtls_config.dart';

/// Connection state for the WebSocket client.
enum ConnectionState {
  /// Not connected to the server.
  disconnected,

  /// Currently connecting.
  connecting,

  /// Connected and ready.
  connected,

  /// Connection failed with error.
  error,
}

/// Event emitted by the WebSocket client.
sealed class WebSocketEvent {}

/// Connection state changed.
class ConnectionStateEvent extends WebSocketEvent {
  /// Creates a connection state event.
  ConnectionStateEvent(this.state, [this.error]);

  /// The new connection state.
  final ConnectionState state;

  /// Error if state is [ConnectionState.error].
  final Object? error;
}

/// Server message received.
class MessageReceivedEvent extends WebSocketEvent {
  /// Creates a message received event.
  MessageReceivedEvent(this.message);

  /// The received server message.
  final ServerMessage message;
}

/// Raw message received (for unknown message types).
class RawMessageEvent extends WebSocketEvent {
  /// Creates a raw message event.
  RawMessageEvent(this.data);

  /// Raw message data.
  final dynamic data;
}

/// WebSocket client for secure communication with Cryptic server.
///
/// This is a low-level client that handles:
/// - mTLS WebSocket connection
/// - Message serialization/deserialization
/// - Connection state tracking
/// - Event streaming
///
/// For automatic reconnection and message queuing, use [ConnectionManager].
class WebSocketClient {
  /// Creates a WebSocket client.
  WebSocketClient({
    required this.mtlsConfig,
    this.path = '/ws',
  });

  /// mTLS configuration for the connection.
  final MtlsConfig mtlsConfig;

  /// WebSocket endpoint path.
  final String path;

  WebSocket? _socket;
  ConnectionState _state = ConnectionState.disconnected;
  final _eventController = StreamController<WebSocketEvent>.broadcast();
  StreamSubscription<dynamic>? _socketSubscription;

  /// Current connection state.
  ConnectionState get state => _state;

  /// Whether the client is connected.
  bool get isConnected => _state == ConnectionState.connected;

  /// Stream of WebSocket events.
  Stream<WebSocketEvent> get events => _eventController.stream;

  /// Stream of server messages only.
  Stream<ServerMessage> get messages => events
      .where((e) => e is MessageReceivedEvent)
      .cast<MessageReceivedEvent>()
      .map((e) => e.message);

  /// Connect to the WebSocket server.
  ///
  /// Uses mTLS for mutual authentication.
  /// Throws [WebSocketException] if connection fails.
  Future<void> connect() async {
    if (_state == ConnectionState.connecting) {
      return; // Already connecting
    }

    if (_state == ConnectionState.connected) {
      return; // Already connected
    }

    _setState(ConnectionState.connecting);

    try {
      final url = mtlsConfig.getWebSocketUrl(path: path);
      AppLogger.info('WebSocket connecting to: $url', tag: 'WebSocket');
      final context = mtlsConfig.createSecurityContext();

      // Create HTTP client with mTLS
      final httpClient = HttpClient(context: context);
      httpClient.badCertificateCallback = (cert, host, port) => true;

      // Connect WebSocket
      _socket = await WebSocket.connect(
        url,
        customClient: httpClient,
      );

      _socketSubscription = _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      AppLogger.info('WebSocket connected successfully', tag: 'WebSocket');
      _setState(ConnectionState.connected);
    } catch (e, stackTrace) {
      AppLogger.error('WebSocket connection failed', 
          tag: 'WebSocket', error: e, stackTrace: stackTrace,);
      _setState(ConnectionState.error, e);
      rethrow;
    }
  }

  /// Disconnect from the WebSocket server.
  Future<void> disconnect() async {
    if (_socket != null) {
      await _socketSubscription?.cancel();
      await _socket!.close();
      _socket = null;
      _socketSubscription = null;
    }
    _setState(ConnectionState.disconnected);
  }

  /// Send a protocol message to the server.
  ///
  /// Throws [StateError] if not connected.
  void send(ProtocolMessage message) {
    if (!isConnected || _socket == null) {
      throw StateError('WebSocket is not connected');
    }

    final json = ProtocolCodec.encode(message);
    AppLogger.debug('WebSocket TX: ${message.type}', tag: 'WebSocket');
    print('[WebSocket] Sending: $json');
    _socket!.add(json);
  }

  /// Send raw JSON string to the server.
  ///
  /// Throws [StateError] if not connected.
  void sendRaw(String json) {
    if (!isConnected || _socket == null) {
      throw StateError('WebSocket is not connected');
    }

    _socket!.add(json);
  }

  /// Dispose the client and release resources.
  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
  }

  void _setState(ConnectionState newState, [Object? error]) {
    print('[WebSocket] State change: $_state -> $newState${error != null ? ' (error: $error)' : ''}');
    _state = newState;
    _eventController.add(ConnectionStateEvent(newState, error));
  }

  void _onData(dynamic data) {
    if (data is String) {
      print('[WebSocket] _onData received: ${data.length > 200 ? data.substring(0, 200) : data}');
      final message = ProtocolCodec.decode(data);
      if (message != null) {
        print('[WebSocket] Decoded message type: ${message.type}');
        AppLogger.debug('WebSocket RX: ${message.type}', tag: 'WebSocket');
        _eventController.add(MessageReceivedEvent(message));
      } else {
        print('[WebSocket] Failed to decode message');
        AppLogger.debug('WebSocket RX (raw): ${data.substring(0, data.length > 100 ? 100 : data.length)}...', tag: 'WebSocket');
        _eventController.add(RawMessageEvent(data));
      }
    } else {
      print('[WebSocket] _onData received binary: ${data.runtimeType}');
      AppLogger.debug('WebSocket RX (binary): ${data.runtimeType}', tag: 'WebSocket');
      _eventController.add(RawMessageEvent(data));
    }
  }

  void _onError(Object error) {
    _setState(ConnectionState.error, error);
  }

  void _onDone() {
    final closeCode = _socket?.closeCode;
    final closeReason = _socket?.closeReason;
    print('[WebSocket] _onDone called - connection closed (code=$closeCode, reason=$closeReason)');
    AppLogger.warning('WebSocket connection closed (_onDone called, code=$closeCode, reason=$closeReason)', tag: 'WebSocket');
    _socket = null;
    _socketSubscription = null;
    if (_state != ConnectionState.disconnected) {
      _setState(ConnectionState.disconnected);
    }
  }
}

/// Exception thrown by WebSocket operations.
class WebSocketClientException implements Exception {
  /// Creates a WebSocket client exception.
  const WebSocketClientException(this.message, [this.cause]);

  /// Error message.
  final String message;

  /// Underlying cause, if any.
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'WebSocketClientException: $message (caused by: $cause)';
    }
    return 'WebSocketClientException: $message';
  }
}
