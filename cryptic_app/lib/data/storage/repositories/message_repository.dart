// lib/data/storage/repositories/message_repository.dart
//
// Message Repository — clean facade over MessageDatabase.

import '../../../domain/models/conversation.dart';
import '../../../domain/models/message.dart';
import '../message_database.dart';

/// Repository for persisting and querying chat messages.
class MessageRepository {
  MessageRepository({required MessageDatabase database}) : _db = database;

  final MessageDatabase _db;

  /// Save a chat message (insert or replace).
  Future<void> saveMessage(ChatMessage message) async {
    if (!_db.isOpen) return;
    await _db.ensureConversation(message.conversationId);
    await _db.insertMessage(message);
  }

  /// Save a message and increment unread count for the conversation.
  Future<void> saveIncomingMessage(ChatMessage message) async {
    if (!_db.isOpen) return;
    await _db.ensureConversation(message.conversationId);
    await _db.insertMessage(message);
    await _db.incrementUnread(message.conversationId);
  }

  /// Load messages for a conversation (newest [limit], ascending).
  Future<List<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 200,
  }) async {
    if (!_db.isOpen) return [];
    return _db.getMessages(conversationId, limit: limit);
  }

  /// Mark a conversation as read.
  Future<void> markAsRead(String peerUsername) async {
    if (!_db.isOpen) return;
    await _db.markAsRead(peerUsername);
  }

  /// Delete a conversation and all its messages.
  Future<void> deleteConversation(String peerUsername) async {
    if (!_db.isOpen) return;
    await _db.deleteConversation(peerUsername);
  }

  /// Load all conversations with the last message for each.
  Future<List<Conversation>> loadConversations() async {
    if (!_db.isOpen) return [];
    final rows = await _db.loadConversations();
    return rows.map(_rowToConversation).toList();
  }

  Conversation _rowToConversation(ConversationRow row) {
    ChatMessage? lastMessage;
    if (row.lastMessageId != null) {
      lastMessage = ChatMessage(
        id: row.lastMessageId!,
        conversationId: row.peerUsername,
        senderId: row.lastMessageSender ?? '',
        content: row.lastMessageContent ?? '',
        timestamp: row.lastMessageTimestamp ?? row.createdAt,
        direction: row.lastMessageDirection ?? MessageDirection.incoming,
        status: row.lastMessageStatus ?? MessageStatus.delivered,
      );
    }

    return Conversation(
      id: row.peerUsername,
      peerUsername: row.peerUsername,
      lastMessage: lastMessage,
      lastMessageAt: row.lastMessageTimestamp,
      unreadCount: row.unreadCount,
      isPinned: row.isPinned,
      isMuted: row.isMuted,
      isArchived: row.isArchived,
      createdAt: row.createdAt,
    );
  }
}
