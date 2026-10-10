import 'package:cryptic_app/core/utils/event_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summarizeFrame shows routing fields but hides key material', () {
    const frame = '{"type":"message","from":"kalle","to":"tobbe","message":'
        '{"message_type":"ratchet","message_id":"kalle-1-2","dh_step":23,'
        '"msg_number":8,"dh_public":"pbb6J9YqkuIQ3nrsTzygI8X7kB0HTZNLnU9RWoh2m3U=",'
        '"ciphertext":"9GWe8axJlivBbtlClCcKAQ==","nonce":"xNJ7bPYeou+64xS7"}}';
    final summary = summarizeFrame(frame);

    expect(summary, contains('from=kalle'));
    expect(summary, contains('msg_number=8'));
    expect(summary, contains('dh_step=23'));
    expect(summary, contains('message_id=kalle-1-2'));
    expect(summary, isNot(contains('pbb6J9')));
    expect(summary, isNot(contains('9GWe8')));
    expect(summary, contains('ciphertext=<24 chars>'));
  });

  test('keeps only the newest entries', () {
    EventLog.instance.clear();
    for (var i = 0; i < EventLog.maxEntries + 10; i++) {
      EventLog.add('T', '$i');
    }
    expect(EventLog.instance.entries.length, EventLog.maxEntries);
    expect(EventLog.instance.entries.first.text, '10');
  });
}
