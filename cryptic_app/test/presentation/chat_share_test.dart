import 'dart:io';
import 'dart:typed_data';

import 'package:cryptic_app/data/engine/payload_codec.dart';
import 'package:cryptic_app/data/services/incoming_share_service.dart';
import 'package:cryptic_app/presentation/providers/incoming_share_provider.dart';
import 'package:cryptic_app/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Sending fails in these tests: the media store's platform channel is not
// registered, so every attempt reaches the error path. That is what the
// cleanup rules must cover.

/// Waits for real file I/O, which fake-async widget tests cannot advance,
/// then for [done] to become true.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    // Advance fake time so queued snackbars are shown in turn.
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('chat_share_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File copy(String name, int bytes) =>
      File('${tempDir.path}/$name')..writeAsBytesSync(Uint8List(bytes));

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    List<IncomingShare> shares,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(incomingShareProvider.notifier).add(shares);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ChatScreen(peerId: 'bob', takeSharedFiles: true),
        ),
      ),
    );
    return container;
  }

  testWidgets('every copy is deleted after a failed send attempt',
      (tester) async {
    final first = copy('a.txt', 10);
    final second = copy('b.txt', 10);
    await pumpChat(tester, [
      IncomingShare(path: first.path, mimeType: 'text/plain'),
      IncomingShare(path: second.path, mimeType: 'text/plain'),
    ]);

    await _settle(tester, () => !first.existsSync() && !second.existsSync());

    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isFalse);
    expect(find.textContaining('Could not send attachment'), findsWidgets);
  });

  testWidgets('oversize copy is skipped, named once, and still deleted',
      (tester) async {
    final big = copy('movie.mp4', AttachmentLimits.maxFileBytes + 1);
    final small = copy('note.txt', 10);
    await pumpChat(tester, [
      IncomingShare(path: big.path, mimeType: 'video/mp4'),
      IncomingShare(path: small.path, mimeType: 'text/plain'),
    ]);

    await _settle(tester, () => !big.existsSync() && !small.existsSync());
    await _settle(
      tester,
      () => find.textContaining('Not sent').evaluate().isNotEmpty,
    );

    expect(big.existsSync(), isFalse);
    expect(small.existsSync(), isFalse);
    // Skipped files are reported together, by name and size.
    expect(
      find.textContaining(
        'Not sent, over the 10 MB limit: movie.mp4 (10.0 MB)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('copies are deleted when the screen closes mid-loop',
      (tester) async {
    final files = [for (var i = 0; i < 3; i++) copy('f$i.bin', 10)];
    await pumpChat(tester, [
      for (final f in files) IncomingShare(path: f.path, mimeType: 'x/y'),
    ]);

    // Close the screen while the first attempt is still doing file I/O.
    await tester.pumpWidget(const SizedBox());

    await _settle(tester, () => files.every((f) => !f.existsSync()));

    for (final f in files) {
      expect(f.existsSync(), isFalse, reason: f.path);
    }
  });
}
