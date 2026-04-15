/// Conversation domain model.
///
/// Represents a conversation (chat thread) with a peer.
library;

import 'message.dart';

/// Conversation entity.
///
/// Represents a chat thread with a specific peer. Contains
/// metadata about the conversation state and session.
class Conversation {
  /// Creates a conversation.
  const Conversation({
    required this.id,
    required this.peerUsername,
    this.peerDisplayName,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.hasActiveSession = false,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.createdAt,
  });

  /// Unique conversation identifier.
  final String id;

  /// The peer's username.
  final String peerUsername;

  /// The peer's display name (if set).
  final String? peerDisplayName;

  /// The last message in the conversation (if any).
  final ChatMessage? lastMessage;

  /// Timestamp of the last message.
  final DateTime? lastMessageAt;

  /// Number of unread messages.
  final int unreadCount;

  /// Whether there's an active Double Ratchet session.
  final bool hasActiveSession;

  /// Whether the conversation is pinned.
  final bool isPinned;

  /// Whether notifications are muted.
  final bool isMuted;

  /// Whether the conversation is archived.
  final bool isArchived;

  /// When the conversation was created.
  final DateTime? createdAt;

  /// Get the display name (peer display name or username).
  String get displayName => peerDisplayName ?? peerUsername;

  /// Whether there are unread messages.
  bool get hasUnread => unreadCount > 0;

  /// Create a copy with updated fields.
  Conversation copyWith({
    String? id,
    String? peerUsername,
    String? peerDisplayName,
    ChatMessage? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? hasActiveSession,
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    DateTime? createdAt,
  }) => Conversation(
      id: id ?? this.id,
      peerUsername: peerUsername ?? this.peerUsername,
      peerDisplayName: peerDisplayName ?? this.peerDisplayName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      hasActiveSession: hasActiveSession ?? this.hasActiveSession,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
    );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conversation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Conversation(id: $id, peer: $peerUsername, unread: $unreadCount)';
}
