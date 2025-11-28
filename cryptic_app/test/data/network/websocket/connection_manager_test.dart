import 'package:cryptic_app/data/network/websocket/connection_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionConfig', () {
    test('should have sensible defaults', () {
      const config = ConnectionConfig();

      expect(config.initialReconnectDelay, const Duration(seconds: 1));
      expect(config.maxReconnectDelay, const Duration(seconds: 60));
      expect(config.reconnectBackoffMultiplier, 2.0);
      expect(config.maxReconnectAttempts, 10);
      expect(config.heartbeatInterval, const Duration(seconds: 30));
      expect(config.connectionTimeout, const Duration(seconds: 10));
      expect(config.enableAutoReconnect, true);
      expect(config.enableHeartbeat, true);
      expect(config.enableMessageQueue, true);
    });

    test('should allow custom values', () {
      const config = ConnectionConfig(
        initialReconnectDelay: Duration(milliseconds: 500),
        maxReconnectDelay: Duration(seconds: 30),
        reconnectBackoffMultiplier: 1.5,
        maxReconnectAttempts: 5,
        heartbeatInterval: Duration(seconds: 15),
        connectionTimeout: Duration(seconds: 5),
        enableAutoReconnect: false,
        enableHeartbeat: false,
        enableMessageQueue: false,
      );

      expect(config.initialReconnectDelay, const Duration(milliseconds: 500));
      expect(config.maxReconnectDelay, const Duration(seconds: 30));
      expect(config.reconnectBackoffMultiplier, 1.5);
      expect(config.maxReconnectAttempts, 5);
      expect(config.heartbeatInterval, const Duration(seconds: 15));
      expect(config.connectionTimeout, const Duration(seconds: 5));
      expect(config.enableAutoReconnect, false);
      expect(config.enableHeartbeat, false);
      expect(config.enableMessageQueue, false);
    });
  });

  group('Connection Events', () {
    test('ConnectedEvent should be creatable', () {
      final event = ConnectedEvent();
      expect(event, isA<ConnectionEvent>());
    });

    test('DisconnectedEvent should store reason and reconnect flag', () {
      final event = DisconnectedEvent(
        reason: 'Connection lost',
        willReconnect: true,
      );

      expect(event.reason, 'Connection lost');
      expect(event.willReconnect, true);
    });

    test('DisconnectedEvent should default to not reconnecting', () {
      final event = DisconnectedEvent();

      expect(event.willReconnect, false);
      expect(event.reason, isNull);
    });

    test('ReconnectingEvent should store attempt info', () {
      final event = ReconnectingEvent(
        attempt: 3,
        maxAttempts: 10,
        delay: const Duration(seconds: 4),
      );

      expect(event.attempt, 3);
      expect(event.maxAttempts, 10);
      expect(event.delay, const Duration(seconds: 4));
    });

    test('ReconnectionFailedEvent should store error', () {
      final event = ReconnectionFailedEvent(
        error: 'Max attempts reached',
      );

      expect(event.error, 'Max attempts reached');
    });

    test('QueueFlushedEvent should store message count', () {
      final event = QueueFlushedEvent(messageCount: 5);

      expect(event.messageCount, 5);
    });
  });
}
