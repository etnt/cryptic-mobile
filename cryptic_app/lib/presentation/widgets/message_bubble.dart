/// Message bubble widget.
///
/// Displays a chat message with appropriate styling for
/// incoming and outgoing messages.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/message.dart';

/// A chat message bubble.
class MessageBubble extends StatelessWidget {
  /// Creates a message bubble.
  const MessageBubble({
    required this.message,
    super.key,
    this.showSender = false,
    this.showTimestamp = true,
  });

  /// The message to display.
  final ChatMessage message;

  /// Whether to show the sender name (for group chats).
  final bool showSender;

  /// Whether to show the timestamp.
  final bool showTimestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOutgoing = message.isOutgoing;

    final bubbleColor = isOutgoing
        ? (isDark ? AppColors.bubbleOutgoingDark : AppColors.bubbleOutgoingLight)
        : (isDark ? AppColors.bubbleIncomingDark : AppColors.bubbleIncomingLight);

    final textColor = isOutgoing && isDark
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: isOutgoing ? 48 : 8,
          right: isOutgoing ? 8 : 48,
          top: 2,
          bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
            bottomRight: Radius.circular(isOutgoing ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender && !isOutgoing)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.senderId,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                fontSize: 16,
                color: textColor,
                height: 1.3,
              ),
            ),
            if (showTimestamp) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTimestamp(message.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
                  if (isOutgoing) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message.status, textColor),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.lock,
                    size: 12,
                    color: AppColors.encrypted.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status, Color color) => switch (status) {
      MessageStatus.pending => Icon(
          Icons.access_time,
          size: 14,
          color: color.withValues(alpha: 0.5),
        ),
      MessageStatus.sending => Icon(
          Icons.access_time,
          size: 14,
          color: color.withValues(alpha: 0.5),
        ),
      MessageStatus.sent => Icon(
          Icons.check,
          size: 14,
          color: color.withValues(alpha: 0.6),
        ),
      MessageStatus.delivered => Icon(
          Icons.done_all,
          size: 14,
          color: color.withValues(alpha: 0.6),
        ),
      MessageStatus.read => const Icon(
          Icons.done_all,
          size: 14,
          color: AppColors.primary,
        ),
      MessageStatus.failed => const Icon(
          Icons.error_outline,
          size: 14,
          color: AppColors.error,
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
      return 'Yesterday ${DateFormat.Hm().format(timestamp)}';
    } else if (now.difference(timestamp).inDays < 7) {
      return DateFormat.E().add_Hm().format(timestamp);
    } else {
      return DateFormat.MMMd().add_Hm().format(timestamp);
    }
  }
}
