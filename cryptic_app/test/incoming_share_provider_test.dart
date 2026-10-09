import 'dart:async';
import 'dart:io';

import 'package:cryptic_app/data/services/incoming_share_service.dart';
import 'package:cryptic_app/presentation/providers/incoming_share_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class _FakeSharingIntent extends ReceiveSharingIntent {
  _FakeSharingIntent(this.initial, {required this.controller});

  final List<SharedMediaFile> initial;
  final StreamController<List<SharedMediaFile>> controller;
  int resetCount = 0;

  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => initial;

  @override
  Stream<List<SharedMediaFile>> getMediaStream() => controller.stream;

  @override
  Future<dynamic> reset() async {
    resetCount++;
  }
}

SharedMediaFile _media(String path, SharedMediaType type, {String? mime}) =>
    SharedMediaFile(path: path, type: type, mimeType: mime);

void main() {
  late Directory tempDir;
  late _FakeSharingIntent plugin;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('share_test');
  });

  tearDown(() async {
    container.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  _FakeSharingIntent createFake([List<SharedMediaFile> initial = const []]) {
    final controller = StreamController<List<SharedMediaFile>>.broadcast();
    addTearDown(controller.close);
    return _FakeSharingIntent(initial, controller: controller);
  }

  ProviderContainer build(List<SharedMediaFile> initial) {
    final controller = StreamController<List<SharedMediaFile>>.broadcast();
    addTearDown(controller.close);
    plugin = _FakeSharingIntent(initial, controller: controller);
    return ProviderContainer(
      overrides: [
        incomingShareServiceProvider.overrideWithValue(
          IncomingShareService(plugin: plugin),
        ),
      ],
    );
  }

  test('initial share is pending, then consumed and cleared', () async {
    final photo = '${tempDir.path}/photo.jpg';
    container = build([
      _media(photo, SharedMediaType.image, mime: 'image/jpeg'),
      _media('hello', SharedMediaType.text),
    ]);
    final notifier = container.read(incomingShareProvider.notifier);

    await notifier.start();

    // Text is skipped; the photo is pending.
    final pending = container.read(incomingShareProvider);
    expect(pending, hasLength(1));
    expect(pending.single.path, photo);
    expect(pending.single.mimeType, 'image/jpeg');
    expect(pending.single.fileName, 'photo.jpg');
    expect(plugin.resetCount, 1, reason: 'initial media is consumed once');

    // Consuming hands the items over and clears the pending list.
    final consumed = notifier.consume();
    expect(consumed, pending);
    expect(container.read(incomingShareProvider), isEmpty);
  });

  test('shares arriving while running are added to pending', () async {
    container = build([]);
    final notifier = container.read(incomingShareProvider.notifier);
    await notifier.start();

    plugin.controller.add([
      _media('${tempDir.path}/a.pdf', SharedMediaType.file),
    ]);
    await Future<void>.delayed(Duration.zero);

    final pending = container.read(incomingShareProvider);
    expect(pending, hasLength(1));
    expect(pending.single.mimeType, 'application/pdf');
  });

  test('discard clears pending shares and deletes their copies', () async {
    final copy = File('${tempDir.path}/secret.png')..writeAsBytesSync([1, 2]);
    container = build([_media(copy.path, SharedMediaType.image)]);
    final notifier = container.read(incomingShareProvider.notifier);
    await notifier.start();

    await notifier.discard();

    expect(container.read(incomingShareProvider), isEmpty);
    expect(copy.existsSync(), isFalse);
  });

  test('start is idempotent', () async {
    container = build([_media('${tempDir.path}/x.jpg', SharedMediaType.image)]);
    final notifier = container.read(incomingShareProvider.notifier);
    await notifier.start();
    await notifier.start();

    expect(container.read(incomingShareProvider), hasLength(1));
    expect(plugin.resetCount, 1);
  });

  test('sweep deletes stale plugin copies and their thumbnails', () async {
    final old = DateTime.now().subtract(const Duration(minutes: 10));
    // A fallback-named copy and its video preview, named `<copy name>.png`.
    final staleCopy = File('${tempDir.path}/IMG_1000.jpg')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(old);
    final staleThumbnail = File('${tempDir.path}/VID_1004.mp4.png')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(old);
    // Not a name the share plugin writes: swept files only match plugin
    // copy naming.
    final other = File('${tempDir.path}/report.txt')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(old);

    plugin = createFake();
    container = ProviderContainer(
      overrides: [
        incomingShareServiceProvider.overrideWithValue(
          IncomingShareService(
            plugin: plugin,
            shareCacheDirectory: () async => tempDir,
          ),
        ),
      ],
    );
    await container.read(incomingShareProvider.notifier).start();

    expect(staleCopy.existsSync(), isFalse);
    expect(staleThumbnail.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
  });

  test('sweep keeps non-share PNGs older than the grace window', () async {
    final old = DateTime.now().subtract(const Duration(minutes: 10));
    // Arbitrary PNG names that the plugin never writes: a display-named
    // video preview and an unrelated image are never swept.
    final preview = File('${tempDir.path}/movie.mp4.png')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(old);
    final image = File('${tempDir.path}/holiday.png')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(old);

    plugin = createFake();
    container = ProviderContainer(
      overrides: [
        incomingShareServiceProvider.overrideWithValue(
          IncomingShareService(
            plugin: plugin,
            shareCacheDirectory: () async => tempDir,
          ),
        ),
      ],
    );
    await container.read(incomingShareProvider.notifier).start();

    expect(preview.existsSync(), isTrue);
    expect(image.existsSync(), isTrue);
  });

  test('sweep keeps files written inside the grace window', () async {
    // Within the grace window: a just-written copy is never deleted.
    final freshCopy = File('${tempDir.path}/IMG_1001.jpg')
      ..writeAsBytesSync([1]);
    final freshPng = File('${tempDir.path}/VID_1005.mp4.png')
      ..writeAsBytesSync([1]);

    plugin = createFake();
    container = ProviderContainer(
      overrides: [
        incomingShareServiceProvider.overrideWithValue(
          IncomingShareService(
            plugin: plugin,
            shareCacheDirectory: () async => tempDir,
          ),
        ),
      ],
    );
    await container.read(incomingShareProvider.notifier).start();

    expect(freshCopy.existsSync(), isTrue);
    expect(freshPng.existsSync(), isTrue);
  });

  test('sweep keeps pending shares and their thumbnails', () async {
    final old = DateTime.now().subtract(const Duration(minutes: 10));
    final pendingCopy = File('${tempDir.path}/IMG_1002.jpg')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(old);
    final pendingThumbnail = File('${tempDir.path}/VID_1002.mp4.png')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(old);

    plugin = createFake([
      SharedMediaFile(
        path: pendingCopy.path,
        type: SharedMediaType.video,
        mimeType: 'video/mp4',
        thumbnail: pendingThumbnail.path,
      ),
    ]);
    container = ProviderContainer(
      overrides: [
        incomingShareServiceProvider.overrideWithValue(
          IncomingShareService(
            plugin: plugin,
            shareCacheDirectory: () async => tempDir,
          ),
        ),
      ],
    );
    await container.read(incomingShareProvider.notifier).start();

    expect(pendingCopy.existsSync(), isTrue);
    expect(pendingThumbnail.existsSync(), isTrue);
  });
}
