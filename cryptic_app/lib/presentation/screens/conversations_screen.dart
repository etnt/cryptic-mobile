/// Conversations list screen.
///
/// Displays the list of active conversations.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/engine_provider.dart';
import '../providers/messages_provider.dart';
import '../widgets/connection_status_banner.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/empty_state.dart';
import 'chat_screen.dart';
import 'users_screen.dart';

/// Screen showing all conversations.
class ConversationsScreen extends ConsumerWidget {
  /// Creates a conversations screen.
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(connectionStatusProvider);
    final conversations = ref.watch(sortedConversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cryptic'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // TODO: Navigate to settings
            },
          ),
        ],
      ),
      body: Column(
        children: [
          ConnectionStatusBanner(
            status: connectionStatus,
            onTap: () {
              // TODO: Attempt reconnect
            },
          ),
          Expanded(
            child: conversations.isEmpty
                ? EmptyState.noConversations(
                    onStartChat: () => _navigateToUsers(context),
                  )
                : ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      return ConversationTile(
                        conversation: conversation,
                        onTap: () => _navigateToChat(
                            context, ref, conversation.peerUsername),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToUsers(context),
        child: const Icon(Icons.chat),
      ),
    );
  }

  void _navigateToUsers(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const UsersScreen(),
      ),
    );
  }

  void _navigateToChat(BuildContext context, WidgetRef ref, String peerId) {
    // Set the selected peer
    ref.read(selectedPeerProvider.notifier).state = peerId;
    // Mark as read
    ref.read(conversationsProvider.notifier).markAsRead(peerId);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChatScreen(peerId: peerId),
      ),
    );
  }
}
