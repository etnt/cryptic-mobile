/// Chat message domain model and attachment metadata.
library;

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

enum MessageStatus { pending, sending, sent, delivered, read, failed }

enum MessageDirection { outgoing, incoming }

enum MessageKind { text, image, file }

enum TransferStatus { none, pending, sending, receiving, complete, failed }

/// A chat message with optional attachment metadata.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.timestamp,
    required this.direction,
    this.status = MessageStatus.sent,
    this.readAt,
    this.deliveredAt,
    this.failureReason,
    this.isDeleted = false,
    this.replyToId,
    this.kind = MessageKind.text,
    this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.localPath,
    this.fileId,
    this.transferProgress,
    this.transferStatus = TransferStatus.none,
  });

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
        id: map['id']! as String,
        conversationId: map['conversation_id']! as String,
        senderId: map['sender_id']! as String,
        content: map['content']! as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp']! as int),
        direction: MessageDirection.values.byName(map['direction']! as String),
        status: MessageStatus.values.byName(map['status']! as String),
        readAt: map['read_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['read_at']! as int),
        deliveredAt: map['delivered_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['delivered_at']! as int),
        failureReason: map['failure_reason'] as String?,
        isDeleted: map['is_deleted'] == true || map['is_deleted'] == 1,
        replyToId: map['reply_to_id'] as String?,
        kind: MessageKind.values.firstWhere(
          (value) => value.name == map['kind'],
          orElse: () => MessageKind.text,
        ),
        fileName: map['file_name'] as String?,
        mimeType: map['mime_type'] as String?,
        sizeBytes: map['size_bytes'] as int?,
        localPath: map['local_path'] as String?,
        fileId: map['file_id'] as String?,
        transferProgress: (map['transfer_progress'] as num?)?.toDouble(),
        transferStatus: TransferStatus.values.firstWhere(
          (value) => value.name == map['transfer_status'],
          orElse: () => TransferStatus.none,
        ),
      );

  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final MessageDirection direction;
  final MessageStatus status;
  final DateTime? readAt;
  final DateTime? deliveredAt;
  final String? failureReason;
  final bool isDeleted;
  final String? replyToId;
  final MessageKind kind;
  final String? fileName;
  final String? mimeType;
  final int? sizeBytes;
  final String? localPath;
  final String? fileId;
  final double? transferProgress;
  final TransferStatus transferStatus;

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    DateTime? timestamp,
    MessageDirection? direction,
    MessageStatus? status,
    DateTime? readAt,
    DateTime? deliveredAt,
    String? failureReason,
    bool? isDeleted,
    String? replyToId,
    MessageKind? kind,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? localPath,
    String? fileId,
    double? transferProgress,
    TransferStatus? transferStatus,
    bool clearLocalPath = false,
    bool clearFailureReason = false,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        senderId: senderId ?? this.senderId,
        content: content ?? this.content,
        timestamp: timestamp ?? this.timestamp,
        direction: direction ?? this.direction,
        status: status ?? this.status,
        readAt: readAt ?? this.readAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        failureReason:
            clearFailureReason ? null : (failureReason ?? this.failureReason),
        isDeleted: isDeleted ?? this.isDeleted,
        replyToId: replyToId ?? this.replyToId,
        kind: kind ?? this.kind,
        fileName: fileName ?? this.fileName,
        mimeType: mimeType ?? this.mimeType,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        localPath: clearLocalPath ? null : (localPath ?? this.localPath),
        fileId: fileId ?? this.fileId,
        transferProgress: transferProgress ?? this.transferProgress,
        transferStatus: transferStatus ?? this.transferStatus,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'direction': direction.name,
        'status': status.name,
        'read_at': readAt?.millisecondsSinceEpoch,
        'delivered_at': deliveredAt?.millisecondsSinceEpoch,
        'failure_reason': failureReason,
        'is_deleted': isDeleted,
        'reply_to_id': replyToId,
        'kind': kind.name,
        'file_name': fileName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'local_path': localPath,
        'file_id': fileId,
        'transfer_progress': transferProgress,
        'transfer_status': transferStatus.name,
      };

  bool get isOutgoing => direction == MessageDirection.outgoing;
  bool get isFailed => status == MessageStatus.failed;
  bool get isPending =>
      status == MessageStatus.pending || status == MessageStatus.sending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChatMessage(id: $id, from: $senderId, status: $status)';
}
