/// Reassembles encrypted-ratchet attachment chunks into private local files.
library;

import 'dart:async';
import 'dart:typed_data';

import '../storage/media_store.dart';
import 'engine_state.dart';
import 'payload_codec.dart';

class FileReassembler {
  FileReassembler({
    required MediaStore mediaStore,
    this.transferTimeout = const Duration(minutes: 10),
  }) : _mediaStore = mediaStore;

  final MediaStore _mediaStore;
  final Duration transferTimeout;
  final Map<String, _Transfer> _transfers = {};
  final _events = StreamController<EngineEvent>.broadcast();
  bool _isDisposed = false;

  Stream<EngineEvent> get events => _events.stream;

  Future<FileReceived?> addChunk({
    required String fromUser,
    required Payload payload,
    required DateTime timestamp,
  }) async {
    if (_isDisposed) {
      throw StateError('FileReassembler has been disposed');
    }
    if (payload.kind != PayloadKind.fileChunk) return null;
    final fileId = payload.fileId!;
    final key = '$fromUser\u0000$fileId';
    final total = payload.totalChunks!;
    final declaredSize = payload.sizeBytes!;
    if (declaredSize < 1 || declaredSize > AttachmentLimits.maxFileBytes) {
      _emitPayloadFailure(fromUser, payload);
      return null;
    }
    final expectedTotal = (declaredSize + AttachmentLimits.chunkBytes - 1) ~/
        AttachmentLimits.chunkBytes;
    final expectedChunkLength = payload.index == total - 1
        ? declaredSize - AttachmentLimits.chunkBytes * (total - 1)
        : AttachmentLimits.chunkBytes;
    if (total != expectedTotal ||
        payload.bytes!.length != expectedChunkLength) {
      final transfer = _transfers[key];
      if (transfer != null) {
        _discard(key, failed: true);
      } else {
        _emitPayloadFailure(fromUser, payload);
      }
      return null;
    }
    var transfer = _transfers[key];
    if (transfer == null) {
      final senderTransfers = _transfers.values
          .where((active) => active.fromUser == fromUser)
          .length;
      if (senderTransfers >= 4) {
        _removeOldestTransfer(fromUser);
      }
      transfer = _Transfer(
        fromUser: fromUser,
        fileId: fileId,
        fileName: _safeFileName(payload.fileName!),
        mimeType: payload.mimeType!,
        sizeBytes: declaredSize,
        totalChunks: total,
      );
      _transfers[key] = transfer;
    } else if (transfer.totalChunks != total ||
        transfer.sizeBytes != declaredSize ||
        transfer.mimeType != payload.mimeType ||
        transfer.fileName != _safeFileName(payload.fileName!)) {
      _discard(key, failed: true);
      return null;
    }

    transfer.timeout?.cancel();
    transfer.timeout = Timer(transferTimeout, () => _expire(key));
    final chunk = payload.bytes!;
    if (!transfer.chunks.containsKey(payload.index)) {
      transfer.receivedBytes += chunk.length;
      if (transfer.receivedBytes > transfer.sizeBytes ||
          transfer.receivedBytes > AttachmentLimits.maxFileBytes) {
        _discard(key, failed: true);
        return null;
      }
      transfer.chunks[payload.index!] = chunk;
    }
    final progressEvent = FileReceiveProgress(
      fromUser: fromUser,
      fileId: fileId,
      fileName: transfer.fileName,
      mimeType: transfer.mimeType,
      sizeBytes: transfer.sizeBytes,
      receivedChunks: transfer.chunks.length,
      totalChunks: total,
      progress: transfer.chunks.length / total,
    );
    _emitEvent(progressEvent);

    if (transfer.chunks.length != total) return null;
    if (transfer.receivedBytes != transfer.sizeBytes) {
      _discard(key, failed: true);
      return null;
    }

    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < total; i++) {
      final part = transfer.chunks[i];
      if (part == null) {
        _discard(key, failed: true);
        return null;
      }
      builder.add(part);
    }
    // Remove the completed transfer before awaiting disk I/O so a late
    // duplicate chunk cannot start a second save/complete event.
    _discard(key);
    final String path;
    try {
      path = await _mediaStore.save(
        peer: fromUser,
        fileId: fileId,
        fileName: transfer.fileName,
        bytes: builder.takeBytes(),
      );
    } catch (_) {
      _emitFailure(transfer);
      rethrow;
    }
    return FileReceived(
      messageId: fileId,
      fromUser: fromUser,
      fileId: fileId,
      fileName: transfer.fileName,
      mimeType: transfer.mimeType,
      sizeBytes: transfer.sizeBytes,
      localPath: path,
      timestamp: timestamp,
    );
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final transfer in _transfers.values) {
      transfer.timeout?.cancel();
    }
    _transfers.clear();
    _events.close();
  }

  void _removeOldestTransfer(String fromUser) {
    // Map iteration order is insertion order, so this removes the earliest
    // active transfer for this sender.
    final oldestKey = _transfers.entries
        .firstWhere((entry) => entry.value.fromUser == fromUser)
        .key;
    _discard(oldestKey, failed: true);
  }

  void _discard(String key, {bool failed = false}) {
    final transfer = _transfers.remove(key);
    transfer?.timeout?.cancel();
    if (failed && transfer != null) _emitFailure(transfer);
  }

  void _emitPayloadFailure(String fromUser, Payload payload) {
    final total = payload.totalChunks ?? 1;
    _emitEvent(
      FileReceiveProgress(
        fromUser: fromUser,
        fileId: payload.fileId ?? '',
        fileName: payload.fileName ?? 'attachment',
        mimeType: payload.mimeType ?? 'application/octet-stream',
        sizeBytes: payload.sizeBytes ?? 0,
        receivedChunks: 0,
        totalChunks: total,
        progress: 0,
        failed: true,
      ),
    );
  }

  void _emitFailure(_Transfer transfer) {
    _emitEvent(
      FileReceiveProgress(
        fromUser: transfer.fromUser,
        fileId: transfer.fileId,
        fileName: transfer.fileName,
        mimeType: transfer.mimeType,
        sizeBytes: transfer.sizeBytes,
        receivedChunks: transfer.chunks.length,
        totalChunks: transfer.totalChunks,
        progress: transfer.chunks.length / transfer.totalChunks,
        failed: true,
      ),
    );
  }

  void _emitEvent(EngineEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  void _expire(String key) {
    final transfer = _transfers.remove(key);
    if (transfer == null) return;
    transfer.timeout?.cancel();
    _emitFailure(transfer);
  }

  static String _safeFileName(String name) {
    final normalized = name.replaceAll(r'\', '/').split('/').last;
    final safe = normalized.replaceAll(RegExp(r'[\x00-\x1F]'), '').trim();
    if (safe.isEmpty || safe == '.' || safe == '..') return 'attachment';
    return safe.length > 255 ? safe.substring(0, 255) : safe;
  }
}

class _Transfer {
  _Transfer({
    required this.fromUser,
    required this.fileId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.totalChunks,
  });

  final String fromUser;
  final String fileId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int totalChunks;
  final Map<int, Uint8List> chunks = {};
  int receivedBytes = 0;
  Timer? timeout;
}
