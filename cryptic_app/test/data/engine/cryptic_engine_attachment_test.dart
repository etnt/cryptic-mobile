import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptic_app/data/crypto/keys/key_bundle.dart';
import 'package:cryptic_app/data/crypto/keys/key_generator.dart';
import 'package:cryptic_app/data/crypto/ratchet/ratchet_state.dart';
import 'package:cryptic_app/data/crypto/x3dh/x3dh_engine.dart';
import 'package:cryptic_app/data/engine/cryptic_engine.dart';
import 'package:cryptic_app/data/engine/engine_state.dart';
import 'package:cryptic_app/data/engine/payload_codec.dart';
import 'package:cryptic_app/data/network/protocol/protocol_message.dart';
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

class _EngineHarness {
  _EngineHarness({
    required this.engine,
    required this.webSocketEvents,
    required this.webSocketMessages,
  });

  final CrypticEngine engine;
  final StreamController<WebSocketEvent> webSocketEvents;
  final StreamController<ServerMessage> webSocketMessages;
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      RatchetState(
        rootKey: Uint8List(32),
        sendChainKey: Uint8List(32),
        sendMessageNumber: 0,
        recvChainKey: Uint8List(32),
        recvMessageNumber: 0,
        prevRecvChainLength: 0,
        dhSelf: (Uint8List(32), Uint8List(32)),
        dhRatchetStep: 0,
        sendingChainActive: false,
        receivingChainActive: false,
        createdAt: DateTime(2025),
      ),
    );
  });

  test('successful X3DH file chunk establishes the peer session', () async {
    final keyGenerator = KeyGenerator();
    final senderKeys = await keyGenerator.generateFullKeyBundle();
    final receiverKeys = await keyGenerator.generateFullKeyBundle();
    final harness = _createHarness(ownKeys: receiverKeys);
    await harness.engine.initialize();
    final sessionCreated = Completer<void>();
    final stateSubscription = harness.engine.stateChanges.listen((state) {
      if ((state.sessions['alice']?.hasSession ?? false) &&
          !sessionCreated.isCompleted) {
        sessionCreated.complete();
      }
    });

    final chunk = PayloadCodec.encodeFileChunk(
      fileId: 'partial-file',
      fileName: 'archive.bin',
      mimeType: 'application/octet-stream',
      sizeBytes: AttachmentLimits.chunkBytes + 1,
      index: 0,
      totalChunks: 2,
      bytes: Uint8List(AttachmentLimits.chunkBytes),
    );
    final encrypted = await X3dhEngine().senderInit(
      senderKeys: senderKeys,
      recipientBundle: receiverKeys.toPublicBundle('bob'),
      plaintext: chunk,
    );
    final blob = encrypted.messageBlob;
    final incoming = IncomingMessage(
      messageType: EncryptedMessageType.x3dh,
      fromUser: 'alice',
      toUser: 'bob',
      rawData: {
        'message_type': 'x3dh',
        'message_id': 'wire-message-id',
        'from': 'alice',
        'to': 'bob',
        'metadata':
            base64Encode(utf8.encode(jsonEncode(blob.metadata.toMap()))),
        'signature': base64Encode(blob.signature),
        'ciphertext': base64Encode(blob.ciphertext),
        'nonce': base64Encode(blob.nonce),
      },
    );

    harness.webSocketMessages.add(incoming);
    await sessionCreated.future.timeout(const Duration(seconds: 5));

    expect(harness.engine.state.sessions['alice']?.hasSession, isTrue);
    await stateSubscription.cancel();
    await harness.engine.dispose();
  });

  test('key-bundle timeout emits file failure and engine error at 30 seconds',
      () {
    fakeAsync((async) {
      final harness = _createHarness();
      final events = <EngineEvent>[];
      final subscription = harness.engine.events.listen(events.add);
      var initialized = false;
      harness.engine.initialize().then((_) => initialized = true);
      async.flushMicrotasks();
      expect(initialized, isTrue);

      harness.webSocketEvents.add(
        ConnectionStateEvent(ConnectionState.connected),
      );
      async.flushMicrotasks();
      var sendCompleted = false;
      harness.engine
          .sendFile(
            'peer',
            Uint8List.fromList([1, 2, 3]),
            'x.bin',
            'application/octet-stream',
          )
          .then((_) => sendCompleted = true);
      async.flushMicrotasks();
      expect(sendCompleted, isTrue);

      async
        ..elapse(const Duration(seconds: 30))
        ..flushMicrotasks();

      expect(
        events.whereType<FileSendProgress>().where((event) => event.failed),
        hasLength(1),
      );
      expect(
        events.whereType<EngineError>().map((event) => event.message),
        contains('File transfer failed: no key bundle received from peer'),
      );
      subscription.cancel();
      harness.engine.dispose();
      async.flushMicrotasks();
    });
  });
}

_EngineHarness _createHarness({OwnKeyBundle? ownKeys}) {
  final keyRepository = MockKeyRepository();
  final sessionRepository = MockSessionRepository();
  final webSocketClient = MockWebSocketClient();
  final webSocketEvents = StreamController<WebSocketEvent>.broadcast();
  final webSocketMessages = StreamController<ServerMessage>.broadcast();
  addTearDown(() async {
    await webSocketEvents.close();
    await webSocketMessages.close();
  });

  when(keyRepository.hasIdentityKeys).thenAnswer((_) async => true);
  when(sessionRepository.listPeers).thenAnswer((_) async => []);
  when(
    () => sessionRepository.saveSession(
      peerUsername: any(named: 'peerUsername'),
      state: any(named: 'state'),
    ),
  ).thenAnswer((_) async {});
  when(() => sessionRepository.hasProcessedMessage(any()))
      .thenAnswer((_) async => false);
  when(() => sessionRepository.markMessageProcessed(any()))
      .thenAnswer((_) async {});
  when(() => keyRepository.consumeOneTimePrekey(any()))
      .thenAnswer((_) async {});
  if (ownKeys != null) {
    when(keyRepository.loadOwnKeyBundle).thenAnswer((_) async => ownKeys);
  }

  when(() => webSocketClient.events).thenAnswer((_) => webSocketEvents.stream);
  when(() => webSocketClient.messages)
      .thenAnswer((_) => webSocketMessages.stream);
  when(webSocketClient.disconnect).thenAnswer((_) async {});

  return _EngineHarness(
    engine: CrypticEngine(
      username: 'bob',
      serverConfig: const ServerConfig(host: 'localhost', port: 8443),
      keyRepository: keyRepository,
      sessionRepository: sessionRepository,
      webSocketClient: webSocketClient,
    ),
    webSocketEvents: webSocketEvents,
    webSocketMessages: webSocketMessages,
  );
}
