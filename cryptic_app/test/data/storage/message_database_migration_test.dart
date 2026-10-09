import 'package:cryptic_app/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy database message rows default to text attachments', () {
    final message = ChatMessage.fromMap(const {
      'id': 'legacy',
      'conversation_id': 'peer',
      'sender_id': 'peer',
      'content': 'hello',
      'timestamp': 1735689600000,
      'direction': 'incoming',
      'status': 'delivered',
      'read_at': null,
      'delivered_at': null,
      'failure_reason': null,
      'is_deleted': 0,
      'reply_to_id': null,
    });

    expect(message.kind, MessageKind.text);
    expect(message.fileId, isNull);
    expect(message.localPath, isNull);
    expect(message.transferStatus, TransferStatus.none);
  });
}
