import 'package:cryptic_app/data/network/websocket/websocket_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionState', () {
    test('should have all expected states', () {
      expect(ConnectionState.values, contains(ConnectionState.disconnected));
      expect(ConnectionState.values, contains(ConnectionState.connecting));
      expect(ConnectionState.values, contains(ConnectionState.connected));
      expect(ConnectionState.values, contains(ConnectionState.error));
    });
  });

  group('WebSocketEvent', () {
    test('ConnectionStateEvent should store state and error', () {
      final event = ConnectionStateEvent(
        ConnectionState.error,
        'Network error',
      );

      expect(event.state, ConnectionState.error);
      expect(event.error, 'Network error');
    });

    test('ConnectionStateEvent should allow null error', () {
      final event = ConnectionStateEvent(ConnectionState.connected);

      expect(event.state, ConnectionState.connected);
      expect(event.error, isNull);
    });

    test('RawMessageEvent should store data', () {
      final event = RawMessageEvent({'key': 'value'});

      expect(event.data, {'key': 'value'});
    });
  });

  group('WebSocketClientException', () {
    test('should format without cause', () {
      const exception = WebSocketClientException('Test error');

      expect(exception.toString(), 'WebSocketClientException: Test error');
    });

    test('should format with cause', () {
      const exception = WebSocketClientException(
        'Test error',
        'underlying cause',
      );

      expect(
        exception.toString(),
        'WebSocketClientException: Test error (caused by: underlying cause)',
      );
    });

    test('should store message and cause', () {
      const exception = WebSocketClientException('message', 'cause');

      expect(exception.message, 'message');
      expect(exception.cause, 'cause');
    });
  });
}
