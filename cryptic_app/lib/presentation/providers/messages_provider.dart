/// Messages provider.
///
/// Manages message state and history for conversations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage/repositories/message_repository.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/message.dart';

/// Provider for all conversations.
///
/// In a real implementation, this would load from storage.
final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, List<Conversation>>((ref) => ConversationsNotifier());

/// Notifier for managing conversations.
class ConversationsNotifier extends StateNotifier<List<Conversation>> {
  /// Creates a conversations notifier.
  ConversationsNotifier() : super([]);

  /// Add or update a conversation.
  void upsertConversation(Conversation conversation) {
    final index = state.indexWhere((c) => c.peerUsername == conversation.peerUsername);
    if (index >= 0) {
      state = [...state]..[index] = conversation;
    } else {
      state = [...state, conversation];
    }
  }

  /// Add a message to a conversation.
  void addMessage(String peerUsername, ChatMessage message) {
    final index = state.indexWhere((c) => c.peerUsername == peerUsername);
    if (index >= 0) {
      final conversation = state[index];
      final updated = conversation.copyWith(
        lastMessage: message,
        lastMessageAt: message.timestamp,
        unreadCount: message.direction == MessageDirection.incoming
            ? conversation.unreadCount + 1
            : conversation.unreadCount,
      );
      state = [...state]..[index] = updated;
    } else {
      // Create new conversation
      final conversation = Conversation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        peerUsername: peerUsername,
        lastMessage: message,
        lastMessageAt: message.timestamp,
        unreadCount: message.direction == MessageDirection.incoming ? 1 : 0,
      );
      state = [...state, conversation];
    }
  }

  /// Mark a conversation as read.
  void markAsRead(String peerUsername) {
    final index = state.indexWhere((c) => c.peerUsername == peerUsername);
    if (index >= 0) {
      final conversation = state[index];
      if (conversation.unreadCount > 0) {
        state = [...state]..[index] = conversation.copyWith(unreadCount: 0);
      }
    }
  }

  /// Delete a conversation.
  void deleteConversation(String peerUsername) {
    state = state.where((c) => c.peerUsername != peerUsername).toList();
  }

  /// Clear all conversations.
  void clear() {
    state = [];
  }

  /// Load conversations from the message database.
  Future<void> loadConversations(MessageRepository repo) async {
    final conversations = await repo.loadConversations();
    state = conversations;
  }
}

/// Provider for the currently selected conversation peer.
final selectedPeerProvider = StateProvider<String?>((ref) => null);

/// Provider for the current conversation.
final currentConversationProvider = Provider<Conversation?>((ref) {
  final peerUsername = ref.watch(selectedPeerProvider);
  if (peerUsername == null) return null;

  final conversations = ref.watch(conversationsProvider);
  try {
    return conversations.firstWhere((c) => c.peerUsername == peerUsername);
  } catch (_) {
    return null;
  }
});

/// Provider for unread message count across all conversations.
final totalUnreadCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsProvider);
  return conversations.fold(0, (sum, c) => sum + c.unreadCount);
});

/// Provider for sorted conversations (most recent first).
final sortedConversationsProvider = Provider<List<Conversation>>((ref) {
  final conversations = ref.watch(conversationsProvider);
  final sorted = List<Conversation>.from(conversations);
  sorted.sort((a, b) {
    final aTime = a.lastMessageAt;
    final bTime = b.lastMessageAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  });
  return sorted;
});

