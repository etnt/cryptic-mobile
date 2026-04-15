/// Chat Message domain model.
///
/// Represents a message in the chat system.
library;

/// Message status enum.
enum MessageStatus {
  /// Message is pending to be sent.
  pending,

  /// Message is being sent.
  sending,

  /// Message has been sent to server.
  sent,

  /// Message has been delivered to recipient.
  delivered,

  /// Message has been read by recipient.
  read,

  /// Message failed to send.
  failed,
}

/// Message direction enum.
enum MessageDirection {
  /// Message sent by current user.
  outgoing,

  /// Message received from another user.
  incoming,
}

/// Chat message entity.
///
/// Represents a single message in a conversation. Contains both
/// the decrypted content and metadata about the message state.
class ChatMessage {
  /// Creates a chat message.
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
  });

  /// Unique message identifier.
  final String id;

  /// The conversation this message belongs to.
  final String conversationId;

  /// Username of the sender.
  final String senderId;

  /// Decrypted message content.
  final String content;

  /// When the message was created/sent.
  final DateTime timestamp;

  /// Whether this is an outgoing or incoming message.
  final MessageDirection direction;

  /// Current message status.
  final MessageStatus status;

  /// When the message was read (if applicable).
  final DateTime? readAt;

  /// When the message was delivered (if applicable).
  final DateTime? deliveredAt;

  /// Reason for failure (if status is failed).
  final String? failureReason;

  /// Whether the message has been deleted.
  final bool isDeleted;

  /// ID of message this is replying to (if any).
  final String? replyToId;

  /// Create a copy with updated fields.
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
  }) => ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      readAt: readAt ?? this.readAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      failureReason: failureReason ?? this.failureReason,
      isDeleted: isDeleted ?? this.isDeleted,
      replyToId: replyToId ?? this.replyToId,
    );

  /// Whether this message is from the current user.
  bool get isOutgoing => direction == MessageDirection.outgoing;

  /// Whether this message failed to send.
  bool get isFailed => status == MessageStatus.failed;

  /// Whether this message is pending.
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
  String toString() =>
      'ChatMessage(id: $id, from: $senderId, status: $status)';
}
