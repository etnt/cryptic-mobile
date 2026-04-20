/// Chat screen.
///
/// Displays messages for a single conversation with input.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/engine/engine_state.dart';
import '../../domain/models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/engine_provider.dart';
import '../providers/messages_provider.dart';
import '../widgets/connection_status_banner.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

/// Screen for chatting with a specific peer.
class ChatScreen extends ConsumerStatefulWidget {
  /// Creates a chat screen.
  const ChatScreen({
    required this.peerId,
    super.key,
  });

  /// The peer's ID (username).
  final String peerId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final repo = ref.read(messageRepositoryProvider);
    if (repo == null) return;

    final history = await repo.getMessages(widget.peerId);
    if (mounted && history.isNotEmpty) {
      setState(() {
        _messages.insertAll(0, history);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    // Mark conversation as read now that we're viewing it
    await repo.markAsRead(widget.peerId);
    ref.read(conversationsProvider.notifier).markAsRead(widget.peerId);
  }

  void _addIncomingMessage(MessageReceived event) {
    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: widget.peerId,
      senderId: event.fromUser,
      content: event.plaintext,
      timestamp: event.timestamp,
      direction: MessageDirection.incoming,
      status: MessageStatus.delivered,
    );

    setState(() {
      _messages.add(message);
    });

    // Persist to database
    ref.read(messageRepositoryProvider)?.saveIncomingMessage(message);

    // Update conversation for last message display
    ref.read(conversationsProvider.notifier).addMessage(widget.peerId, message);

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage(String text) async {
    // Create a pending message
    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: widget.peerId,
      senderId: 'me', // TODO(M8): Get from auth provider
      content: text,
      timestamp: DateTime.now(),
      direction: MessageDirection.outgoing,
      status: MessageStatus.pending,
    );

    // Add to local messages list
    setState(() {
      _messages.add(message);
    });

    // Persist to database
    ref.read(messageRepositoryProvider)?.saveMessage(message);

    // Add to conversation (for last message display)
    ref.read(conversationsProvider.notifier).addMessage(widget.peerId, message);

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Send via engine
    final engine = ref.read(engineProvider);
    print('[ChatScreen] Sending message to ${widget.peerId}: $text');
    await engine?.sendMessage(widget.peerId, text);
  }

  Future<void> _resetSession() async {
    final engine = ref.read(engineProvider);
    if (engine == null) return;

    print('[ChatScreen] Resetting session with ${widget.peerId}');
    await engine.clearSession(widget.peerId);
    
    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session with ${widget.peerId} reset'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(connectionStatusProvider);
    final hasSession = ref.watch(hasSessionProvider(widget.peerId));

    // Listen for incoming messages from this peer
    ref.listen<AsyncValue<EngineEvent>>(engineEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event is MessageReceived && event.fromUser == widget.peerId) {
          print('[ChatScreen] Received message from ${event.fromUser}: ${event.plaintext}');
          _addIncomingMessage(event);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.peerId),
            if (hasSession)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock,
                    size: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Encrypted',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showChatMenu(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          ConnectionStatusBanner(
            status: connectionStatus,
            onTap: () {
              // TODO(M8): Attempt reconnect
            },
          ),
          Expanded(
            child: _messages.isEmpty
                ? EmptyState.noMessages()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final showTimestamp = _shouldShowTimestamp(
                        _messages,
                        index,
                      );
                      return Column(
                        children: [
                          if (showTimestamp)
                            _buildTimestampDivider(
                              context,
                              message.timestamp,
                            ),
                          MessageBubble(
                            message: message,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          MessageInput(
            enabled: connectionStatus == ConnectionStatus.connected,
            onSubmit: _sendMessage,
            placeholder: connectionStatus == ConnectionStatus.connected
                ? 'Type a message...'
                : 'Connecting...',
          ),
        ],
      ),
    );
  }

  bool _shouldShowTimestamp(List<ChatMessage> messages, int index) {
    if (index == 0) return true;

    final current = messages[index].timestamp;
    final previous = messages[index - 1].timestamp;

    // Show timestamp if more than 30 minutes apart
    return current.difference(previous).inMinutes > 30;
  }

  Widget _buildTimestampDivider(BuildContext context, DateTime timestamp) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        _formatDate(timestamp),
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showChatMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Verify identity'),
              onTap: () {
                Navigator.pop(context);
                // TODO(M8): Show fingerprint verification
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Reset session'),
              onTap: () {
                Navigator.pop(context);
                _resetSession();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete conversation',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteConversation(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteConversation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This will delete all messages in this conversation. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(conversationsProvider.notifier)
                  .deleteConversation(widget.peerId);
              ref
                  .read(messageRepositoryProvider)
                  ?.deleteConversation(widget.peerId);
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to conversations
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
