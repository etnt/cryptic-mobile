import 'dart:io';
import 'dart:typed_data';

import 'package:cryptic_app/data/engine/engine_state.dart';
import 'package:cryptic_app/data/engine/file_reassembler.dart';
import 'package:cryptic_app/data/engine/payload_codec.dart';
import 'package:cryptic_app/data/storage/media_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  late FileReassembler reassembler;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('cryptic-media-test');
    reassembler = FileReassembler(
      mediaStore: MediaStore(documentsDirectoryProvider: () async => documents),
    );
  });

  tearDown(() async {
    reassembler.dispose();
    await documents.delete(recursive: true);
  });

  final firstPart = Uint8List.fromList(
    List<int>.generate(AttachmentLimits.chunkBytes, (index) => index % 256),
  );
  const lastPart = [4, 5, 6];
  final fileSize = AttachmentLimits.chunkBytes + lastPart.length;

  Payload chunk(int index, List<int> bytes) => Payload.fileChunk(
        fileId: 'transfer',
        fileName: '../photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: fileSize,
        index: index,
        totalChunks: 2,
        bytes: Uint8List.fromList(bytes),
      );

  test('reassembles out-of-order chunks and sanitizes the file name', () async {
    expect(
      await reassembler.addChunk(
        fromUser: 'peer',
        payload: chunk(1, lastPart),
        timestamp: DateTime(2025),
      ),
      isNull,
    );
    final received = await reassembler.addChunk(
      fromUser: 'peer',
      payload: chunk(0, firstPart),
      timestamp: DateTime(2025),
    );
    expect(received, isNotNull);
    expect(received!.fileName, 'photo.jpg');
    expect(
      received.localPath,
      matches(r'/media/peer_[0-9a-f]{8}/transfer_[0-9a-f]{8}\.jpg$'),
    );
    expect(
      await File(received.localPath).readAsBytes(),
      [...firstPart, ...lastPart],
    );
  });

  test('does not complete when a chunk is missing', () async {
    final result = await reassembler.addChunk(
      fromUser: 'peer',
      payload: chunk(0, firstPart),
      timestamp: DateTime(2025),
    );
    expect(result, isNull);
    // Tests may use async IO.
    // ignore: avoid_slow_async_io
    expect(await Directory('${documents.path}/media').exists(), isFalse);
  });

  test('per-sender transfer cap reports the evicted transfer as failed',
      () async {
    final events = <EngineEvent>[];
    final subscription = reassembler.events.listen(events.add);
    final data = Uint8List(AttachmentLimits.chunkBytes);
    for (var i = 0; i < 5; i++) {
      await reassembler.addChunk(
        fromUser: 'peer',
        payload: Payload.fileChunk(
          fileId: 'cap-$i',
          fileName: 'file.bin',
          mimeType: 'application/octet-stream',
          sizeBytes: AttachmentLimits.chunkBytes + 1,
          index: 0,
          totalChunks: 2,
          bytes: data,
        ),
        timestamp: DateTime(2025),
      );
    }
    expect(
      events.whereType<FileReceiveProgress>().where((event) => event.failed),
      hasLength(1),
    );
    expect(
      events
          .whereType<FileReceiveProgress>()
          .singleWhere((event) => event.failed)
          .fileId,
      'cap-0',
    );
    await subscription.cancel();
  });

  test('metadata mismatch reports a failed transfer', () async {
    final events = <EngineEvent>[];
    final subscription = reassembler.events.listen(events.add);
    await reassembler.addChunk(
      fromUser: 'peer',
      payload: chunk(0, firstPart),
      timestamp: DateTime(2025),
    );
    await reassembler.addChunk(
      fromUser: 'peer',
      payload: Payload.fileChunk(
        fileId: 'transfer',
        fileName: 'different.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: fileSize,
        index: 1,
        totalChunks: 2,
        bytes: Uint8List.fromList(lastPart),
      ),
      timestamp: DateTime(2025),
    );
    expect(
      events.whereType<FileReceiveProgress>().last.failed,
      isTrue,
    );
    await subscription.cancel();
  });

  test('rejects chunks after disposal', () async {
    reassembler.dispose();
    await expectLater(
      reassembler.addChunk(
        fromUser: 'peer',
        payload: chunk(0, firstPart),
        timestamp: DateTime(2025),
      ),
      throwsStateError,
    );
  });

  test('rejects a transfer declaring a size above the cap', () async {
    final result = await reassembler.addChunk(
      fromUser: 'peer',
      payload: Payload.fileChunk(
        fileId: 'oversize',
        fileName: 'large.bin',
        mimeType: 'application/octet-stream',
        sizeBytes: AttachmentLimits.maxFileBytes + 1,
        index: 0,
        totalChunks: 1,
        bytes: Uint8List.fromList([1]),
      ),
      timestamp: DateTime(2025),
    );
    expect(result, isNull);
  });
}
