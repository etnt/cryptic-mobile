import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cryptic_app/data/engine/engine_state.dart';

void main() {
  group('ConnectionStatus', () {
    test('should have all expected values', () {
      expect(ConnectionStatus.values, hasLength(5));
      expect(ConnectionStatus.values, contains(ConnectionStatus.disconnected));
      expect(ConnectionStatus.values, contains(ConnectionStatus.connecting));
      expect(ConnectionStatus.values, contains(ConnectionStatus.connected));
      expect(ConnectionStatus.values, contains(ConnectionStatus.reconnecting));
      expect(ConnectionStatus.values, contains(ConnectionStatus.error));
    });
  });

  group('EngineStatus', () {
    test('should have all expected values', () {
      expect(EngineStatus.values, hasLength(5));
      expect(EngineStatus.values, contains(EngineStatus.uninitialized));
      expect(EngineStatus.values, contains(EngineStatus.initializing));
      expect(EngineStatus.values, contains(EngineStatus.ready));
      expect(EngineStatus.values, contains(EngineStatus.needsSetup));
      expect(EngineStatus.values, contains(EngineStatus.failed));
    });
  });

  group('UserIdentity', () {
    test('should create with required fields', () {
      final signKey = Uint8List(32);
      final dhKey = Uint8List(32);

      final identity = UserIdentity(
        username: 'alice',
        identitySignPublicKey: signKey,
        identityDhPublicKey: dhKey,
      );

      expect(identity.username, 'alice');
      expect(identity.identitySignPublicKey, signKey);
      expect(identity.identityDhPublicKey, dhKey);
    });

    test('copyWith should update specified fields', () {
      final identity = UserIdentity(
        username: 'alice',
        identitySignPublicKey: Uint8List(32),
        identityDhPublicKey: Uint8List(32),
      );

      final newDhKey = Uint8List.fromList(List.filled(32, 1));
      final updated = identity.copyWith(identityDhPublicKey: newDhKey);

      expect(updated.username, 'alice');
      expect(updated.identityDhPublicKey, newDhKey);
    });

    test('equality should compare by username', () {
      final identity1 = UserIdentity(
        username: 'alice',
        identitySignPublicKey: Uint8List(32),
        identityDhPublicKey: Uint8List(32),
      );

      final identity2 = UserIdentity(
        username: 'alice',
        identitySignPublicKey: Uint8List.fromList(List.filled(32, 1)),
        identityDhPublicKey: Uint8List.fromList(List.filled(32, 2)),
      );

      final identity3 = UserIdentity(
        username: 'bob',
        identitySignPublicKey: Uint8List(32),
        identityDhPublicKey: Uint8List(32),
      );

      expect(identity1, equals(identity2));
      expect(identity1.hashCode, equals(identity2.hashCode));
      expect(identity1, isNot(equals(identity3)));
    });
  });

  group('ServerConfig', () {
    test('should create with required fields', () {
      final config = ServerConfig(
        host: 'example.com',
        port: 8443,
      );

      expect(config.host, 'example.com');
      expect(config.port, 8443);
      expect(config.path, '/ws');
    });

    test('should allow custom path', () {
      final config = ServerConfig(
        host: 'example.com',
        port: 8443,
        path: '/custom',
      );

      expect(config.path, '/custom');
    });

    test('wsUrl should build correct URL', () {
      final config = ServerConfig(
        host: 'example.com',
        port: 8443,
        path: '/ws',
      );

      expect(config.wsUrl, 'wss://example.com:8443/ws');
    });

    test('copyWith should update specified fields', () {
      final config = ServerConfig(
        host: 'localhost',
        port: 8080,
      );

      final updated = config.copyWith(port: 9000);

      expect(updated.host, 'localhost');
      expect(updated.port, 9000);
    });

    test('equality should work correctly', () {
      final config1 = ServerConfig(host: 'example.com', port: 8443);
      final config2 = ServerConfig(host: 'example.com', port: 8443);
      final config3 = ServerConfig(host: 'other.com', port: 8443);

      expect(config1, equals(config2));
      expect(config1.hashCode, equals(config2.hashCode));
      expect(config1, isNot(equals(config3)));
    });

    test('toString should include all fields', () {
      final config = ServerConfig(host: 'example.com', port: 8443);
      expect(config.toString(), contains('example.com'));
      expect(config.toString(), contains('8443'));
    });
  });

  group('PeerSession', () {
    test('should create with required fields', () {
      final session = PeerSession(
        peerUsername: 'bob',
        hasSession: true,
      );

      expect(session.peerUsername, 'bob');
      expect(session.hasSession, isTrue);
      expect(session.messageCount, 0);
      expect(session.lastMessageAt, isNull);
    });

    test('should create with all fields', () {
      final lastMessage = DateTime(2025, 1, 2);

      final session = PeerSession(
        peerUsername: 'bob',
        hasSession: true,
        messageCount: 42,
        lastMessageAt: lastMessage,
      );

      expect(session.peerUsername, 'bob');
      expect(session.hasSession, isTrue);
      expect(session.messageCount, 42);
      expect(session.lastMessageAt, lastMessage);
    });

    test('copyWith should update specified fields', () {
      final session = PeerSession(
        peerUsername: 'bob',
        hasSession: false,
      );

      final lastMessage = DateTime.now();
      final updated = session.copyWith(
        hasSession: true,
        lastMessageAt: lastMessage,
        messageCount: 5,
      );

      expect(updated.peerUsername, 'bob');
      expect(updated.hasSession, isTrue);
      expect(updated.lastMessageAt, lastMessage);
      expect(updated.messageCount, 5);
    });
  });

  group('EngineState', () {
    test('initial state should have defaults', () {
      const state = EngineState.initial;

      expect(state.status, EngineStatus.uninitialized);
      expect(state.connectionStatus, ConnectionStatus.disconnected);
      expect(state.identity, isNull);
      expect(state.serverConfig, isNull);
      expect(state.sessions, isEmpty);
      expect(state.error, isNull);
      expect(state.keysUploaded, isFalse);
      expect(state.isConnected, isFalse);
      expect(state.isReady, isFalse);
    });

    test('computed properties should work correctly', () {
      final identity = UserIdentity(
        username: 'alice',
        identitySignPublicKey: Uint8List(32),
        identityDhPublicKey: Uint8List(32),
      );

      final state = EngineState(
        status: EngineStatus.ready,
        connectionStatus: ConnectionStatus.connected,
        identity: identity,
        sessions: {
          'bob': PeerSession(peerUsername: 'bob', hasSession: true),
        },
      );

      expect(state.isReady, isTrue);
      expect(state.isConnected, isTrue);
      expect(state.needsSetup, isFalse);
      expect(state.username, 'alice');
      expect(state.sessionCount, 1);
      expect(state.hasError, isFalse);
    });

    test('copyWith should update specified fields', () {
      const state = EngineState.initial;

      final identity = UserIdentity(
        username: 'alice',
        identitySignPublicKey: Uint8List(32),
        identityDhPublicKey: Uint8List(32),
      );

      final updated = state.copyWith(
        status: EngineStatus.ready,
        connectionStatus: ConnectionStatus.connected,
        identity: identity,
      );

      expect(updated.status, EngineStatus.ready);
      expect(updated.connectionStatus, ConnectionStatus.connected);
      expect(updated.identity, identity);
      expect(updated.isConnected, isTrue);
      expect(updated.isReady, isTrue);
    });

    test('withSession should add new session', () {
      const state = EngineState.initial;

      final session = PeerSession(
        peerUsername: 'bob',
        hasSession: true,
      );

      final updated = state.withSession(session);

      expect(updated.sessions, hasLength(1));
      expect(updated.sessions['bob'], session);
    });

    test('withSession should update existing session', () {
      final session1 = PeerSession(
        peerUsername: 'bob',
        hasSession: false,
      );
      final state = EngineState(sessions: {'bob': session1});

      final session2 = session1.copyWith(hasSession: true, messageCount: 5);
      final updated = state.withSession(session2);

      expect(updated.sessions, hasLength(1));
      expect(updated.sessions['bob']?.hasSession, isTrue);
      expect(updated.sessions['bob']?.messageCount, 5);
    });

    test('withoutSession should remove session', () {
      final state = EngineState(
        sessions: {
          'bob': PeerSession(peerUsername: 'bob', hasSession: true),
          'alice': PeerSession(peerUsername: 'alice', hasSession: true),
        },
      );

      final updated = state.withoutSession('bob');

      expect(updated.sessions, hasLength(1));
      expect(updated.sessions.containsKey('bob'), isFalse);
      expect(updated.sessions.containsKey('alice'), isTrue);
    });

    test('withError should set error and failed status', () {
      final state = EngineState(status: EngineStatus.ready);

      final updated = state.withError('Something went wrong');

      expect(updated.status, EngineStatus.failed);
      expect(updated.error, 'Something went wrong');
      expect(updated.hasError, isTrue);
    });

    test('clearingError should remove error', () {
      final state = EngineState(
        status: EngineStatus.failed,
        error: 'Previous error',
      );

      final updated = state.clearingError();

      expect(updated.error, isNull);
      expect(updated.hasError, isFalse);
    });

    test('toString should include key info', () {
      final state = EngineState(
        status: EngineStatus.ready,
        connectionStatus: ConnectionStatus.connected,
      );

      final str = state.toString();
      expect(str, contains('ready'));
      expect(str, contains('connected'));
    });
  });

  group('EngineEvent', () {
    test('EngineStatusChanged should carry status and optional error', () {
      final event = EngineStatusChanged(EngineStatus.ready);
      expect(event.status, EngineStatus.ready);
      expect(event.error, isNull);

      final errorEvent =
          EngineStatusChanged(EngineStatus.failed, 'Init failed');
      expect(errorEvent.status, EngineStatus.failed);
      expect(errorEvent.error, 'Init failed');
    });

    test('ConnectionStatusChanged should carry status', () {
      final event = ConnectionStatusChanged(ConnectionStatus.connected);
      expect(event.status, ConnectionStatus.connected);
    });

    test('SessionUpdated should carry session', () {
      final session = PeerSession(peerUsername: 'bob', hasSession: true);
      final event = SessionUpdated(session);
      expect(event.session, session);
    });

    test('MessageReceived should carry message details', () {
      final timestamp = DateTime.now();
      final event = MessageReceived(
        fromUser: 'alice',
        plaintext: 'Hello!',
        timestamp: timestamp,
      );

      expect(event.fromUser, 'alice');
      expect(event.plaintext, 'Hello!');
      expect(event.timestamp, timestamp);
    });

    test('MessageSent should carry message details', () {
      final timestamp = DateTime.now();
      final event = MessageSent(
        messageId: 'msg-123',
        toUser: 'bob',
        timestamp: timestamp,
      );

      expect(event.messageId, 'msg-123');
      expect(event.toUser, 'bob');
      expect(event.timestamp, timestamp);
    });

    test('UsersListReceived should carry users list', () {
      final event = UsersListReceived(['alice', 'bob', 'charlie']);
      expect(event.users, hasLength(3));
      expect(event.users, contains('alice'));
    });

    test('UserStatusChanged should carry username and status', () {
      final event = UserStatusChanged('bob', true);
      expect(event.username, 'bob');
      expect(event.isOnline, isTrue);
    });

    test('EngineError should carry error details', () {
      final event = EngineError('Connection failed');
      expect(event.message, 'Connection failed');
      expect(event.cause, isNull);

      final eventWithCause =
          EngineError('Network error', Exception('timeout'));
      expect(eventWithCause.message, 'Network error');
      expect(eventWithCause.cause, isA<Exception>());
    });
  });
}
