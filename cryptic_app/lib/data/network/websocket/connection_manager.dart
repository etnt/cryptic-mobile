/// Connection manager for WebSocket with automatic reconnection.
///
/// Provides higher-level connection management including:
/// - Automatic reconnection with exponential backoff
/// - Heartbeat/keepalive
/// - Message queuing when disconnected
/// - Connection event streaming
library;

import 'dart:async';
import 'dart:math';

import '../protocol/protocol_message.dart';
import '../protocol/server_messages.dart';
import 'message_queue.dart';
import 'mtls_config.dart';
import 'websocket_client.dart';

/// Configuration for connection manager behavior.
class ConnectionConfig {
  /// Creates connection configuration.
  const ConnectionConfig({
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 60),
    this.reconnectBackoffMultiplier = 2.0,
    this.maxReconnectAttempts = 10,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.connectionTimeout = const Duration(seconds: 10),
    this.enableAutoReconnect = true,
    this.enableHeartbeat = true,
    this.enableMessageQueue = true,
  });

  /// Initial delay before first reconnection attempt.
  final Duration initialReconnectDelay;

  /// Maximum delay between reconnection attempts.
  final Duration maxReconnectDelay;

  /// Multiplier for exponential backoff.
  final double reconnectBackoffMultiplier;

  /// Maximum number of reconnection attempts (0 = unlimited).
  final int maxReconnectAttempts;

  /// Interval between heartbeat pings.
  final Duration heartbeatInterval;

  /// Timeout for connection attempts.
  final Duration connectionTimeout;

  /// Whether to automatically reconnect on disconnect.
  final bool enableAutoReconnect;

  /// Whether to send heartbeat pings.
  final bool enableHeartbeat;

  /// Whether to queue messages when disconnected.
  final bool enableMessageQueue;

  /// Default configuration.
  static const defaultConfig = ConnectionConfig();
}

/// High-level connection events.
sealed class ConnectionEvent {}

/// Connection established.
class ConnectedEvent extends ConnectionEvent {}

/// Connection closed.
class DisconnectedEvent extends ConnectionEvent {
  /// Creates a disconnected event.
  DisconnectedEvent({this.reason, this.willReconnect = false});

  /// Reason for disconnection.
  final String? reason;

  /// Whether the manager will attempt to reconnect.
  final bool willReconnect;
}

/// Reconnecting after disconnect.
class ReconnectingEvent extends ConnectionEvent {
  /// Creates a reconnecting event.
  ReconnectingEvent({
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
  });

  /// Current attempt number.
  final int attempt;

  /// Maximum attempts (0 = unlimited).
  final int maxAttempts;

  /// Delay before this attempt.
  final Duration delay;
}

/// Reconnection failed.
class ReconnectionFailedEvent extends ConnectionEvent {
  /// Creates a reconnection failed event.
  ReconnectionFailedEvent({required this.error});

  /// The error that caused failure.
  final Object error;
}

/// Message received from server.
class ServerMessageEvent extends ConnectionEvent {
  /// Creates a server message event.
  ServerMessageEvent(this.message);

  /// The received message.
  final ServerMessage message;
}

/// Queued messages were sent after reconnection.
class QueueFlushedEvent extends ConnectionEvent {
  /// Creates a queue flushed event.
  QueueFlushedEvent({required this.messageCount});

  /// Number of messages that were sent.
  final int messageCount;
}

/// Connection manager with automatic reconnection and message queuing.
///
/// This wraps [WebSocketClient] to provide:
/// - Automatic reconnection with exponential backoff
/// - Optional heartbeat/keepalive pings
/// - Message queuing when disconnected
/// - High-level connection events
class ConnectionManager {
  /// Creates a connection manager.
  ConnectionManager({
    required this.mtlsConfig,
    this.config = ConnectionConfig.defaultConfig,
    String path = '/ws',
  }) : _client = WebSocketClient(
          mtlsConfig: mtlsConfig,
          path: path,
          pingInterval:
              config.enableHeartbeat ? config.heartbeatInterval : null,
        );

  /// mTLS configuration.
  final MtlsConfig mtlsConfig;

  /// Connection behavior configuration.
  final ConnectionConfig config;

  final WebSocketClient _client;
  final _eventController = StreamController<ConnectionEvent>.broadcast();
  late final MessageQueue _messageQueue;

  StreamSubscription<WebSocketEvent>? _clientSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = true;
  bool _disposed = false;

  /// Whether the manager is connected.
  bool get isConnected => _client.isConnected;

  /// Current connection state.
  ConnectionState get state => _client.state;

  /// Stream of connection events.
  Stream<ConnectionEvent> get events => _eventController.stream;

  /// Stream of server messages only.
  Stream<ServerMessage> get messages => events
      .where((e) => e is ServerMessageEvent)
      .cast<ServerMessageEvent>()
      .map((e) => e.message);

  /// Number of queued messages waiting to be sent.
  int get queuedMessageCount => _messageQueue.length;

  /// Initialize the connection manager.
  ///
  /// Must be called before [connect].
  void initialize() {
    _messageQueue = MessageQueue(
      maxAge: const Duration(hours: 24),
    );

    _clientSubscription = _client.events.listen(_handleClientEvent);
  }

  /// Connect to the server.
  ///
  /// If already connected, this is a no-op.
  /// If disconnected, starts reconnection cycle if enabled.
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('ConnectionManager has been disposed');
    }

    _shouldReconnect = config.enableAutoReconnect;
    _reconnectAttempts = 0;
    _cancelReconnect();

    await _doConnect();
  }

  /// Disconnect from the server.
  ///
  /// Stops any pending reconnection attempts.
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _cancelReconnect();
    await _client.disconnect();
    _eventController.add(DisconnectedEvent());
  }

  /// Send a protocol message.
  ///
  /// If connected, sends immediately.
  /// If disconnected and queuing is enabled, queues the message.
  void send(ProtocolMessage message) {
    if (_client.isConnected) {
      _client.send(message);
    } else if (config.enableMessageQueue) {
      _messageQueue.enqueue(message);
    } else {
      throw StateError('Not connected and message queue is disabled');
    }
  }

  /// Dispose the connection manager.
  Future<void> dispose() async {
    _disposed = true;
    _shouldReconnect = false;
    _cancelReconnect();
    await _clientSubscription?.cancel();
    await _client.dispose();
    await _eventController.close();
    _messageQueue.clear();
  }

  Future<void> _doConnect() async {
    try {
      await _client.connect().timeout(config.connectionTimeout);
    } on TimeoutException {
      _handleConnectionFailure(
        TimeoutException('Connection timed out', config.connectionTimeout),
      );
    } catch (e) {
      _handleConnectionFailure(e);
    }
  }

  void _handleClientEvent(WebSocketEvent event) {
    switch (event) {
      case ConnectionStateEvent(state: ConnectionState.connected):
        _onConnected();
      case ConnectionStateEvent(state: ConnectionState.disconnected):
        _onDisconnected();
      case ConnectionStateEvent(state: ConnectionState.error, error: final err):
        _onError(err);
      case MessageReceivedEvent(message: final msg):
        _eventController.add(ServerMessageEvent(msg));
      case RawMessageEvent():
        // Ignore raw messages
        break;
      case ConnectionStateEvent():
        // Ignore connecting state
        break;
    }
  }

  void _onConnected() {
    _reconnectAttempts = 0;
    _eventController.add(ConnectedEvent());
    _flushQueue();
  }

  void _onDisconnected() {
    if (_shouldReconnect && !_disposed) {
      _eventController.add(
        DisconnectedEvent(willReconnect: true),
      );
      _scheduleReconnect();
    } else {
      _eventController.add(
        DisconnectedEvent(),
      );
    }
  }

  void _onError(Object? error) {
    if (_shouldReconnect && !_disposed) {
      _scheduleReconnect();
    }
  }

  void _handleConnectionFailure(Object error) {
    if (_shouldReconnect && !_disposed) {
      _eventController.add(
        DisconnectedEvent(reason: error.toString(), willReconnect: true),
      );
      _scheduleReconnect();
    } else {
      _eventController.add(
        DisconnectedEvent(reason: error.toString()),
      );
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _disposed) return;

    _reconnectAttempts++;

    if (config.maxReconnectAttempts > 0 &&
        _reconnectAttempts > config.maxReconnectAttempts) {
      _eventController.add(
        ReconnectionFailedEvent(
          error: 'Max reconnection attempts reached',
        ),
      );
      _shouldReconnect = false;
      return;
    }

    final delay = _calculateBackoff();

    _eventController.add(
      ReconnectingEvent(
        attempt: _reconnectAttempts,
        maxAttempts: config.maxReconnectAttempts,
        delay: delay,
      ),
    );

    _reconnectTimer = Timer(delay, () {
      if (_shouldReconnect && !_disposed) {
        _doConnect();
      }
    });
  }

  Duration _calculateBackoff() {
    final baseDelay = config.initialReconnectDelay.inMilliseconds;
    final multiplier =
        pow(config.reconnectBackoffMultiplier, _reconnectAttempts - 1);
    final delayMs = (baseDelay * multiplier).round();
    final maxDelayMs = config.maxReconnectDelay.inMilliseconds;

    // Add some jitter (±10%)
    final jitter = (delayMs * 0.1 * (Random().nextDouble() * 2 - 1)).round();
    final finalDelay = min(delayMs + jitter, maxDelayMs);

    return Duration(milliseconds: finalDelay);
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _flushQueue() {
    if (!config.enableMessageQueue) return;

    final messages = _messageQueue.dequeueAll();
    if (messages.isEmpty) return;

    var sentCount = 0;
    for (final message in messages) {
      if (_client.isConnected) {
        try {
          _client.send(message);
          sentCount++;
        } catch (_) {
          // Re-queue failed messages
          _messageQueue.enqueue(message);
        }
      } else {
        // Re-queue if disconnected during flush
        _messageQueue.enqueue(message);
      }
    }

    if (sentCount > 0) {
      _eventController.add(QueueFlushedEvent(messageCount: sentCount));
    }
  }
}
