import 'package:cryptic_app/data/network/protocol/client_messages.dart';
import 'package:cryptic_app/data/network/protocol/protocol_codec.dart';
import 'package:cryptic_app/data/network/protocol/server_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes message acknowledgment', () {
    final message = MessageAckMessage(messageId: 'message-123');

    expect(
      ProtocolCodec.encode(message),
      '{"type":"message_ack","message_id":"message-123"}',
    );
  });

  test('exposes incoming message ID from the encrypted blob', () {
    final message = IncomingMessage.fromJson({
      'type': 'message',
      'from': 'alice',
      'to': 'bob',
      'message': {
        'message_type': 'ratchet',
        'message_id': 'message-123',
      },
    });

    expect(message.messageId, 'message-123');
  });
}
