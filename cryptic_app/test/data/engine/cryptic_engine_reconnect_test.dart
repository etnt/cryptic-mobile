// test/data/engine/cryptic_engine_reconnect_test.dart
//
// Tests the configurable reconnect policy of CrypticEngine:
// - maxReconnectAttempts: 0 → unlimited attempts (background connection)
// - default: gives up after the configured cap
// - backoff is capped at 60 s

import 'dart:async';

import 'package:cryptic_app/data/engine/cryptic_engine.dart';
import 'package:cryptic_app/data/engine/engine_state.dart';
import 'package:cryptic_app/data/network/protocol/server_messages.dart';
import 'package:cryptic_app/data/network/websocket/websocket_client.dart';
import 'package:cryptic_app/data/storage/repositories/key_repository.dart';
import 'package:cryptic_app/data/storage/repositories/session_repository.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockKeyRepository extends Mock implements KeyRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

class MockWebSocketClient extends Mock implements WebSocketClient {}

void main() {
  late MockKeyRepository keyRepository;
  late MockSessionRepository sessionRepository;
  late MockWebSocketClient webSocketClient;
  late StreamController<WebSocketEvent> webSocketEvents;
  late StreamController<ServerMessage> webSocketMessages;

  setUp(() {
    keyRepository = MockKeyRepository();
    sessionRepository = MockSessionRepository();
    webSocketClient = MockWebSocketClient();
    webSocketEvents = StreamController<WebSocketEvent>.broadcast();
    webSocketMessages = StreamController<ServerMessage>.broadcast();

    when(keyRepository.hasIdentityKeys).thenAnswer((_) async => true);
    when(sessionRepository.listPeers).thenAnswer((_) async => []);
    when(() => webSocketClient.events).thenAnswer((_) => webSocketEvents.stream);
    when(() => webSocketClient.messages)
        .thenAnswer((_) => webSocketMessages.stream);
    when(webSocketClient.disconnect).thenAnswer((_) async {});
  });

  tearDown(() async {
    await webSocketEvents.close();
    await webSocketMessages.close();
  });

  CrypticEngine buildEngine({required int maxReconnectAttempts}) => CrypticEngine(
        username: 'bob',
        serverConfig: const ServerConfig(host: 'localhost', port: 8443),
        keyRepository: keyRepository,
        sessionRepository: sessionRepository,
        webSocketClient: webSocketClient,
        maxReconnectAttempts: maxReconnectAttempts,
      );

  /// Signals the engine that the socket hit an error, which is what triggers
  /// the next scheduled reconnect attempt (mirrors real client behavior).
  void emitSocketError() {
    webSocketEvents.add(ConnectionStateEvent(
        ConnectionState.error, WebSocketClientException('unreachable')));
  }

  test('unlimited mode keeps retrying past the default cap', () {
    fakeAsync((async) {
      var connectCalls = 0;
      when(webSocketClient.connect).thenAnswer((_) async {
        connectCalls++;
        throw WebSocketClientException('unreachable');
      });

      final engine = buildEngine(maxReconnectAttempts: 0);
      engine.events.listen((_) {});
      var initialized = false;
      engine.initialize().then((_) => initialized = true);
      async.flushMicrotasks();
      expect(initialized, isTrue);

      // First connect fails (fire and forget - the error is expected).
      unawaited(engine.connect().catchError((Object e) {}));
      async.flushMicrotasks();
      expect(connectCalls, 1);

      // Drive 15 failed reconnect cycles: each cycle = socket error event →
      // schedule reconnect → timer fires → connect fails again. Elapsing
      // 61 s per cycle covers the 60 s backoff cap so every attempt fires.
      for (var i = 0; i < 15; i++) {
        emitSocketError();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 61));
        async.flushMicrotasks();
      }

      // The engine never gave up despite far exceeding the default
      // 10-attempt cap (1 initial + 15 scheduled = 16).
      expect(connectCalls, greaterThanOrEqualTo(16));

      unawaited(engine.dispose());
      async.flushMicrotasks();
    });
  });

  test('default mode gives up after the configured attempt cap', () {
    fakeAsync((async) {
      var connectCalls = 0;
      when(webSocketClient.connect).thenAnswer((_) async {
        connectCalls++;
        throw WebSocketClientException('unreachable');
      });

      final engine = buildEngine(maxReconnectAttempts: 2);
      engine.events.listen((_) {});
      engine.initialize();
      async.flushMicrotasks();

      unawaited(engine.connect().catchError((Object e) {}));
      async.flushMicrotasks();

      // Attempt 1
      emitSocketError();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      // Attempt 2
      emitSocketError();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();

      final callsAfterCap = connectCalls;
      expect(callsAfterCap, 3); // 1 initial + 2 retries

      // A further socket error must NOT schedule another attempt.
      emitSocketError();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(connectCalls, callsAfterCap);

      unawaited(engine.dispose());
      async.flushMicrotasks();
    });
  });

  test('backoff is capped at 60 seconds in unlimited mode', () {
    fakeAsync((async) {
      var connectCalls = 0;
      when(webSocketClient.connect).thenAnswer((_) async {
        connectCalls++;
        throw WebSocketClientException('unreachable');
      });

      final engine = buildEngine(maxReconnectAttempts: 0);
      engine.events.listen((_) {});
      engine.initialize();
      async.flushMicrotasks();

      unawaited(engine.connect().catchError((Object e) {}));
      async.flushMicrotasks();

      // Push attempts far past where an uncapped exponential backoff
      // (2^n seconds) would exceed 60 s. Elapsing 61 s per attempt proves
      // every timer fires within the cap.
      var previousCalls = connectCalls;
      for (var i = 0; i < 12; i++) {
        emitSocketError();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 61));
        async.flushMicrotasks();
        expect(connectCalls, greaterThan(previousCalls),
            reason: 'attempt $i should have fired within the 60 s cap');
        previousCalls = connectCalls;
      }

      unawaited(engine.dispose());
      async.flushMicrotasks();
    });
  });

  test('unlimited mode survives over 1100 attempts without crashing', () {
    fakeAsync((async) {
      var connectCalls = 0;
      when(webSocketClient.connect).thenAnswer((_) async {
        connectCalls++;
        throw WebSocketClientException('unreachable');
      });

      final engine = buildEngine(maxReconnectAttempts: 0);
      engine.events.listen((_) {});
      engine.initialize();
      async.flushMicrotasks();

      unawaited(engine.connect().catchError((Object e) {}));
      async.flushMicrotasks();

      // Regression test: an unclamped pow(2, attempts - 1) returns Infinity
      // once the counter passes ~1025, so (baseMs * multiplier).round()
      // throws UnsupportedError inside _scheduleReconnect and retries silently
      // stop. Drive 1100 cycles to prove the engine survives far past that.
      const attempts = 1100;
      for (var i = 0; i < attempts; i++) {
        emitSocketError();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 61));
        async.flushMicrotasks();
      }

      // 1 initial connect + one retry per driven cycle.
      expect(connectCalls, greaterThanOrEqualTo(attempts));

      unawaited(engine.dispose());
      async.flushMicrotasks();
    });
  });
}
