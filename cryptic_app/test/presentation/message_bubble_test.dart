import 'package:cryptic_app/domain/models/message.dart';
import 'package:cryptic_app/presentation/widgets/linkified_text.dart';
import 'package:cryptic_app/presentation/widgets/message_bubble.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a message URL as a link span', (tester) async {
    final message = ChatMessage(
      id: 'text-id',
      conversationId: 'peer',
      senderId: 'peer',
      content: 'see https://example.com/a?b=1.',
      timestamp: DateTime(2025),
      direction: MessageDirection.incoming,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message)),
      ),
    );

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkifiedText),
        matching: find.byType(RichText),
      ),
    );
    final spans = <InlineSpan>[];
    richText.text.visitChildren((span) {
      spans.add(span);
      return true;
    });

    expect(richText.text.toPlainText(), message.content);
    expect(
      spans.whereType<TextSpan>().map((span) => span.text),
      contains('https://example.com/a?b=1'),
    );
  });

  testWidgets('tapping a message link calls its injected opener',
      (tester) async {
    Uri? openedUri;
    final message = ChatMessage(
      id: 'text-id',
      conversationId: 'peer',
      senderId: 'peer',
      content: 'see https://example.com/a?b=1.',
      timestamp: DateTime(2025),
      direction: MessageDirection.incoming,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            onOpenLink: (uri) async {
              openedUri = uri;
              return true;
            },
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkifiedText),
        matching: find.byType(RichText),
      ),
    );
    TapGestureRecognizer? linkRecognizer;
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == 'https://example.com/a?b=1') {
        linkRecognizer = span.recognizer as TapGestureRecognizer?;
      }
      return true;
    });

    expect(linkRecognizer, isNotNull);
    linkRecognizer?.onTap?.call();
    await tester.pump();

    expect(openedUri, Uri.parse('https://example.com/a?b=1'));
  });

  testWidgets('plain message text renders unchanged', (tester) async {
    const content = 'Just ordinary chat text.';
    final message = ChatMessage(
      id: 'text-id',
      conversationId: 'peer',
      senderId: 'peer',
      content: content,
      timestamp: DateTime(2025),
      direction: MessageDirection.incoming,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message)),
      ),
    );

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkifiedText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.text.toPlainText(), content);
    expect(find.byType(LinkifiedText), findsOneWidget);
  });

  testWidgets('renders attachment name and transfer progress', (tester) async {
    final message = ChatMessage(
      id: 'file-id',
      fileId: 'file-id',
      conversationId: 'peer',
      senderId: 'me',
      content: 'archive.zip',
      timestamp: DateTime(2025),
      direction: MessageDirection.outgoing,
      kind: MessageKind.file,
      fileName: 'archive.zip',
      mimeType: 'application/zip',
      sizeBytes: 1024,
      transferProgress: .5,
      transferStatus: TransferStatus.sending,
      status: MessageStatus.sending,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message)),
      ),
    );

    expect(find.text('archive.zip'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
