/// Versioned plaintext envelope for ratchet messages.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Attachment transfer limits and conservative WebSocket-safe chunk size.
abstract final class AttachmentLimits {
  static const int maxFileBytes = 10 * 1024 * 1024;
  // The codec/base64 + ratchet/base64 and JSON envelope remains comfortably
  // below the server's 64 KiB frame limit with this raw chunk size.
  static const int chunkBytes = 24 * 1024;
  static const int maxFrameBytes = 64 * 1024;
}

enum PayloadKind { text, fileChunk, invalid }

/// A decoded plaintext payload.
class Payload {
  const Payload.invalid()
      : kind = PayloadKind.invalid,
        text = null,
        fileId = null,
        fileName = null,
        mimeType = null,
        sizeBytes = null,
        index = null,
        totalChunks = null,
        bytes = null;

  const Payload.text(this.text)
      : kind = PayloadKind.text,
        fileId = null,
        fileName = null,
        mimeType = null,
        sizeBytes = null,
        index = null,
        totalChunks = null,
        bytes = null;

  const Payload.fileChunk({
    required this.fileId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.index,
    required this.totalChunks,
    required this.bytes,
  })  : kind = PayloadKind.fileChunk,
        text = null;

  final PayloadKind kind;
  final String? text;
  final String? fileId;
  final String? fileName;
  final String? mimeType;
  final int? sizeBytes;
  final int? index;
  final int? totalChunks;
  final Uint8List? bytes;
}

/// Encodes attachment metadata and legacy-compatible text plaintexts.
abstract final class PayloadCodec {
  static const int marker = 0x01;
  static const int version = 1;

  /// Text remains an unmarked UTF-8 string for old-client compatibility.
  static Uint8List encodeText(String text) =>
      Uint8List.fromList(utf8.encode(text));

  /// Split a validated file into bounded views without duplicating its bytes.
  static List<Uint8List> splitFile(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > AttachmentLimits.maxFileBytes) {
      throw ArgumentError('File must be between 1 byte and 10 MB');
    }
    return [
      for (var start = 0;
          start < bytes.length;
          start += AttachmentLimits.chunkBytes)
        Uint8List.sublistView(
          bytes,
          start,
          start + AttachmentLimits.chunkBytes < bytes.length
              ? start + AttachmentLimits.chunkBytes
              : bytes.length,
        ),
    ];
  }

  static Uint8List encodeFileChunk({
    required String fileId,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
    required int index,
    required int totalChunks,
    required Uint8List bytes,
  }) {
    final expectedTotal = sizeBytes > 0
        ? (sizeBytes + AttachmentLimits.chunkBytes - 1) ~/
            AttachmentLimits.chunkBytes
        : 0;
    final expectedChunkBytes = index == totalChunks - 1
        ? sizeBytes - AttachmentLimits.chunkBytes * (totalChunks - 1)
        : AttachmentLimits.chunkBytes;
    if (fileId.isEmpty ||
        fileId.length > 128 ||
        fileName.length > 255 ||
        mimeType.length > 128 ||
        sizeBytes < 1 ||
        sizeBytes > AttachmentLimits.maxFileBytes ||
        totalChunks != expectedTotal ||
        index < 0 ||
        index >= totalChunks ||
        bytes.length != expectedChunkBytes) {
      throw ArgumentError('Invalid attachment chunk metadata');
    }
    final map = <String, Object>{
      'v': version,
      'kind': 'file_chunk',
      'file_id': fileId,
      'file_name': fileName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'index': index,
      'total_chunks': totalChunks,
      'data': base64Encode(bytes),
    };
    final jsonBytes = utf8.encode(jsonEncode(map));
    final result = Uint8List(jsonBytes.length + 1)..[0] = marker;
    result.setRange(1, result.length, jsonBytes);
    // Account for the AEAD tag, outer ciphertext base64, JSON envelope, and
    // ratchet metadata before allowing the plaintext to enter the transport.
    final estimatedFrameBytes = ((result.length + 16 + 2) ~/ 3) * 4 + 2048;
    if (estimatedFrameBytes > AttachmentLimits.maxFrameBytes) {
      throw ArgumentError('Encoded attachment chunk exceeds frame limit');
    }
    return result;
  }

  /// Decodes versioned envelopes; unmarked plaintext is treated as legacy text.
  static Payload decode(Uint8List plaintext) {
    if (plaintext.isEmpty || plaintext.first != marker) {
      return Payload.text(utf8.decode(plaintext, allowMalformed: true));
    }
    try {
      final decoded = jsonDecode(utf8.decode(plaintext.sublist(1)));
      if (decoded is! Map<String, dynamic> ||
          decoded['v'] != version ||
          decoded['kind'] != 'file_chunk') {
        return const Payload.invalid();
      }
      final fileId = decoded['file_id'];
      final fileName = decoded['file_name'];
      final mimeType = decoded['mime_type'];
      final sizeBytes = decoded['size_bytes'];
      final index = decoded['index'];
      final totalChunks = decoded['total_chunks'];
      final data = decoded['data'];
      if (fileId is! String ||
          fileId.isEmpty ||
          fileName is! String ||
          fileName.length > 255 ||
          mimeType is! String ||
          mimeType.length > 128 ||
          fileId.length > 128 ||
          sizeBytes is! int ||
          index is! int ||
          totalChunks is! int ||
          data is! String ||
          sizeBytes < 0 ||
          sizeBytes > AttachmentLimits.maxFileBytes ||
          index < 0 ||
          totalChunks < 1 ||
          index >= totalChunks) {
        throw const FormatException('Invalid attachment payload');
      }
      final bytes = base64Decode(data);
      final expectedTotal = (sizeBytes + AttachmentLimits.chunkBytes - 1) ~/
          AttachmentLimits.chunkBytes;
      final expectedChunkBytes = index == totalChunks - 1
          ? sizeBytes - (AttachmentLimits.chunkBytes * (totalChunks - 1))
          : AttachmentLimits.chunkBytes;
      if (totalChunks != expectedTotal ||
          bytes.length != expectedChunkBytes ||
          bytes.length > AttachmentLimits.chunkBytes) {
        throw const FormatException('Invalid attachment chunk size');
      }
      return Payload.fileChunk(
        fileId: fileId,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        index: index,
        totalChunks: totalChunks,
        bytes: Uint8List.fromList(bytes),
      );
    } catch (_) {
      // Marked payloads are protocol envelopes. Never expose malformed or
      // unsupported envelopes as user-visible plaintext.
      return const Payload.invalid();
    }
  }
}
