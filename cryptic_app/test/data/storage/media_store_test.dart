import 'dart:io';

import 'package:cryptic_app/data/storage/media_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDirectory;
  late MediaStore mediaStore;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp('cryptic-media');
    mediaStore = MediaStore(
      documentsDirectoryProvider: () async => supportDirectory,
    );
  });

  tearDown(() async {
    await supportDirectory.delete(recursive: true);
  });

  test('eviction retains protected files and returns removed paths', () async {
    final retainedPath = await mediaStore.save(
      peer: 'peer',
      fileId: 'retained',
      fileName: 'retained.bin',
      bytes: [1, 2, 3],
    );
    final evictedPath = await mediaStore.save(
      peer: 'peer',
      fileId: 'evicted',
      fileName: 'evicted.bin',
      bytes: [4, 5, 6],
    );
    final oldDate = DateTime.now().subtract(const Duration(days: 40));
    await File(retainedPath).setLastModified(oldDate);
    await File(evictedPath).setLastModified(oldDate);

    final removed = await mediaStore.evict(
      maxMediaCacheMb: 0,
      protectedPaths: {retainedPath},
    );

    expect(removed, [evictedPath]);
    // Tests may use async IO.
    // ignore: avoid_slow_async_io
    expect(await File(retainedPath).exists(), isTrue);
    // Tests may use async IO.
    // ignore: avoid_slow_async_io
    expect(await File(evictedPath).exists(), isFalse);
  });

  test('duplicate save keeps the original attachment bytes', () async {
    final path = await mediaStore.save(
      peer: 'peer',
      fileId: 'same-id',
      fileName: 'attachment.bin',
      bytes: [1, 2, 3],
    );

    await expectLater(
      mediaStore.save(
        peer: 'peer',
        fileId: 'same-id',
        fileName: 'attachment.bin',
        bytes: [4, 5, 6],
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('sanitized peer names remain distinct for colliding names', () async {
    final first = await mediaStore.resolvePath('a/b', 'id');
    final second = await mediaStore.resolvePath('a_b', 'id');
    expect(first, isNot(second));
  });
}
