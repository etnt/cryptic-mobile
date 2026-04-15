/// Conversation tile widget.
///
/// Displays a conversation preview in a list.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/conversation.dart';
import '../../domain/models/message.dart';

/// A list tile showing a conversation preview.
class ConversationTile extends StatelessWidget {
  /// Creates a conversation tile.
  const ConversationTile({
    required this.conversation,
    required this.onTap,
    super.key,
    this.isSelected = false,
  });

  /// The conversation to display.
  final Conversation conversation;

  /// Callback when tile is tapped.
  final VoidCallback onTap;

  /// Whether this tile is selected.
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastMessage = conversation.lastMessage;

    return ListTile(
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      leading: _buildAvatar(theme),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.displayName,
              style: TextStyle(
                fontWeight: conversation.hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conversation.lastMessageAt != null)
            Text(
              _formatTimestamp(conversation.lastMessageAt!),
              style: TextStyle(
                fontSize: 12,
                color: conversation.hasUnread
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: conversation.hasUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (lastMessage != null && lastMessage.isOutgoing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildStatusIcon(lastMessage.status, theme),
            ),
          Expanded(
            child: Text(
              lastMessage?.content ?? 'No messages yet',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: conversation.hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conversation.hasUnread)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                conversation.unreadCount > 99
                    ? '99+'
                    : conversation.unreadCount.toString(),
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildAvatar(ThemeData theme) => CircleAvatar(
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        conversation.displayName.isNotEmpty
            ? conversation.displayName[0].toUpperCase()
            : '?',
        style: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

  Widget _buildStatusIcon(MessageStatus status, ThemeData theme) => switch (status) {
      MessageStatus.pending || MessageStatus.sending => Icon(
          Icons.access_time,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      MessageStatus.sent => Icon(
          Icons.check,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      MessageStatus.delivered => Icon(
          Icons.done_all,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      MessageStatus.read => Icon(
          Icons.done_all,
          size: 16,
          color: theme.colorScheme.primary,
        ),
      MessageStatus.failed => Icon(
          Icons.error_outline,
          size: 16,
          color: theme.colorScheme.error,
        ),
    };

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
    );

    if (messageDate == today) {
      return DateFormat.Hm().format(timestamp);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (now.difference(timestamp).inDays < 7) {
      return DateFormat.E().format(timestamp);
    } else {
      return DateFormat.MMMd().format(timestamp);
    }
  }
}
