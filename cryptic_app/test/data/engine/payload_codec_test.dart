import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptic_app/data/engine/payload_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PayloadCodec', () {
    test('round trips text with the legacy unmarked representation', () {
      final bytes = PayloadCodec.encodeText('hello 🌍');
      expect(bytes.first, isNot(PayloadCodec.marker));
      final payload = PayloadCodec.decode(bytes);
      expect(payload.kind, PayloadKind.text);
      expect(payload.text, 'hello 🌍');
    });

    test('discards malformed marked envelopes instead of treating them as text',
        () {
      final payload = PayloadCodec.decode(
        Uint8List.fromList([PayloadCodec.marker, ...utf8.encode('{broken')]),
      );
      expect(payload.kind, PayloadKind.invalid);
      expect(payload.text, isNull);
    });

    test('discards unsupported marked envelopes', () {
      final payload = PayloadCodec.decode(
        Uint8List.fromList([
          PayloadCodec.marker,
          ...utf8.encode('{"v":2,"kind":"future"}'),
        ]),
      );
      expect(payload.kind, PayloadKind.invalid);
    });

    test('splits files into bounded chunks without dropping trailing bytes',
        () {
      final bytes = Uint8List(AttachmentLimits.chunkBytes * 2 + 7);
      final chunks = PayloadCodec.splitFile(bytes);
      expect(chunks.map((chunk) => chunk.length), [
        AttachmentLimits.chunkBytes,
        AttachmentLimits.chunkBytes,
        7,
      ]);
      expect(chunks.expand((chunk) => chunk).length, bytes.length);
    });

    test('decodes an attachment chunk envelope', () {
      final raw = Uint8List.fromList([1, 2, 3, 4]);
      final encoded = PayloadCodec.encodeFileChunk(
        fileId: 'id1',
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 4,
        index: 0,
        totalChunks: 1,
        bytes: raw,
      );
      final decoded = PayloadCodec.decode(encoded);
      expect(decoded.kind, PayloadKind.fileChunk);
      expect(decoded.fileId, 'id1');
      expect(decoded.bytes, raw);
    });

    test('worst case chunk stays under 64KB after ratchet base64 and JSON', () {
      final envelope = PayloadCodec.encodeFileChunk(
        fileId: 'a' * 32,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: AttachmentLimits.maxFileBytes,
        index: 0,
        totalChunks:
            (AttachmentLimits.maxFileBytes + AttachmentLimits.chunkBytes - 1) ~/
                AttachmentLimits.chunkBytes,
        bytes: Uint8List(AttachmentLimits.chunkBytes),
      );
      final frame = utf8.encode(
        jsonEncode({
          'type': 'ratchet',
          'message_id': 'sender-1234567890',
          'from_user': 'sender',
          'to_user': 'recipient',
          'dh_public': base64Encode(Uint8List(32)),
          'dh_step': 1,
          'previous_chain_length': 10,
          'message_number': 10,
          'ciphertext': base64Encode(Uint8List(envelope.length + 16)),
          'nonce': base64Encode(Uint8List(12)),
        }),
      );
      expect(frame.length, lessThan(AttachmentLimits.maxFrameBytes));
    });
  });
}
