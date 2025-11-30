/// Empty state widget.
///
/// Displays a placeholder when a list is empty.
library;

import 'package:flutter/material.dart';

/// A widget shown when content is empty.
class EmptyState extends StatelessWidget {
  /// Creates an empty state widget.
  const EmptyState({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  /// Factory for no conversations state.
  factory EmptyState.noConversations({VoidCallback? onStartChat}) {
    return EmptyState(
      icon: Icons.chat_bubble_outline,
      title: 'No conversations yet',
      message: 'Start a new chat to begin messaging',
      actionLabel: 'Start Chat',
      onAction: onStartChat,
    );
  }

  /// Factory for no messages state.
  factory EmptyState.noMessages() {
    return const EmptyState(
      icon: Icons.message_outlined,
      title: 'No messages',
      message: 'Send a message to start the conversation',
    );
  }

  /// Factory for no users state.
  factory EmptyState.noUsers({VoidCallback? onRefresh}) {
    return EmptyState(
      icon: Icons.people_outline,
      title: 'No users available',
      message: 'No other users are registered on the server',
      actionLabel: 'Refresh',
      onAction: onRefresh,
    );
  }

  /// The icon to display.
  final IconData icon;

  /// The title text.
  final String title;

  /// Optional message text.
  final String? message;

  /// Optional action button label.
  final String? actionLabel;

  /// Optional action callback.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
