import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptic_app/data/crypto/ratchet/ratchet_message.dart';
import 'package:cryptic_app/data/engine/engine_state.dart';
import 'package:cryptic_app/data/engine/file_reassembler.dart';
import 'package:cryptic_app/data/engine/message_processor.dart';
import 'package:cryptic_app/data/engine/session_manager.dart';
import 'package:cryptic_app/data/network/protocol/protocol_message.dart';
import 'package:cryptic_app/data/network/protocol/server_messages.dart';
import 'package:cryptic_app/data/storage/media_store.dart';
import 'package:cryptic_app/data/storage/repositories/key_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSessionManager extends Mock implements SessionManager {}

class MockKeyRepository extends Mock implements KeyRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      RatchetMessage(
        dhPublic: Uint8List(32),
        dhStep: 0,
        prevChainLength: 0,
        messageNumber: 0,
        ciphertext: Uint8List(1),
        nonce: Uint8List(12),
      ),
    );
  });

  late MockSessionManager sessionManager;
  late MockKeyRepository keyRepository;
  late Directory tempDirectory;
  late FileReassembler fileReassembler;
  late MessageProcessor processor;

  setUp(() async {
    sessionManager = MockSessionManager();
    keyRepository = MockKeyRepository();
    tempDirectory = await Directory.systemTemp.createTemp('cryptic-invalid');
    fileReassembler = FileReassembler(
      mediaStore: MediaStore(
        documentsDirectoryProvider: () async => tempDirectory,
      ),
    );
    processor = MessageProcessor(
      sessionManager: sessionManager,
      keyRepository: keyRepository,
      fileReassembler: fileReassembler,
    );

    when(() => sessionManager.hasProcessedMessage('invalid-message'))
        .thenAnswer((_) async => false);
    when(() => sessionManager.hasSession('peer')).thenReturn(true);
    when(
      () => sessionManager.decryptMessage(
        peerUsername: 'peer',
        message: any(named: 'message'),
      ),
    ).thenAnswer(
      (_) async => Uint8List.fromList([
        1,
        ...utf8.encode('{broken'),
      ]),
    );
    when(() => sessionManager.markMessageProcessed('invalid-message'))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    processor.dispose();
    await tempDirectory.delete(recursive: true);
  });

  test('invalid marked payload is discarded without emitting a message',
      () async {
    final events = <EngineEvent>[];
    final subscription = processor.events.listen(events.add);
    final message = IncomingMessage(
      messageType: EncryptedMessageType.ratchet,
      fromUser: 'peer',
      toUser: 'me',
      rawData: {
        'message_type': 'ratchet',
        'message_id': 'invalid-message',
        'from': 'peer',
        'to': 'me',
        'dh_public': base64Encode(Uint8List(32)),
        'dh_step': 0,
        'prev_chain_length': 0,
        'msg_number': 0,
        'ciphertext': base64Encode([1]),
        'nonce': base64Encode(Uint8List(12)),
      },
    );

    final result = await processor.processMessage(message);

    expect(result, isA<ProcessingSuccess>());
    expect((result as ProcessingSuccess).event, isNull);
    expect(events.whereType<MessageReceived>(), isEmpty);
    await subscription.cancel();
  });
}
