import 'package:cryptic_app/domain/models/message.dart';
import 'package:cryptic_app/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
