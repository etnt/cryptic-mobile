/// Message bubble widget.
///
/// Displays a chat message with appropriate styling for
/// incoming and outgoing messages.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/message.dart';
import 'image_viewer_screen.dart';
import 'linkified_text.dart';

/// A chat message bubble.
class MessageBubble extends StatelessWidget {
  /// Creates a message bubble.
  const MessageBubble({
    required this.message,
    super.key,
    this.showSender = false,
    this.showTimestamp = true,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onOpenLink,
  });

  /// The message to display.
  final ChatMessage message;

  /// Whether to show the sender name (for group chats).
  final bool showSender;

  /// Whether to show the timestamp.
  final bool showTimestamp;

  /// Whether this message is currently selected.
  final bool selected;

  /// Whether the chat is in selection mode (taps toggle selection).
  final bool selectionMode;

  /// Called on tap while in selection mode.
  final VoidCallback? onTap;

  /// Called on long press.
  final VoidCallback? onLongPress;

  /// Optional handler for opening links in text messages.
  final Future<bool> Function(Uri uri)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOutgoing = message.isOutgoing;

    final bubbleColor = isOutgoing
        ? (isDark
            ? AppColors.bubbleOutgoingDark
            : AppColors.bubbleOutgoingLight)
        : (isDark
            ? AppColors.bubbleIncomingDark
            : AppColors.bubbleIncomingLight);

    final textColor = isOutgoing && isDark
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);

    final bubble = Align(
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
            if (message.kind == MessageKind.text)
              LinkifiedText(
                text: message.content,
                style: TextStyle(
                  fontSize: 16,
                  color: textColor,
                  height: 1.3,
                ),
                linkStyle: TextStyle(
                  fontSize: 16,
                  color: isOutgoing && isDark
                      ? Colors.lightBlueAccent
                      : theme.colorScheme.primary,
                  height: 1.3,
                  decoration: TextDecoration.underline,
                ),
                onOpen: onOpenLink,
              )
            else
              _buildAttachment(context, textColor),
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selectionMode ? onTap : null,
      onLongPress: onLongPress,
      child: ColoredBox(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        // In selection mode the bubble's own taps (open image/file) are off.
        child: IgnorePointer(ignoring: selectionMode, child: bubble),
      ),
    );
  }

  Widget _buildAttachment(BuildContext context, Color textColor) {
    final path = message.localPath;
    if (message.kind == MessageKind.image && path != null) {
      return GestureDetector(
        onTap: () {
          // Drop input focus first so the keyboard is not restored on pop.
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ImageViewerScreen(path: path),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(path),
            width: 220,
            height: 180,
            cacheWidth: 660,
            cacheHeight: 540,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 220,
              height: 100,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: path == null
          ? null
          : () {
              if (!_isAllowedToOpen(path, message.mimeType)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Opening this file type is not supported.'),
                  ),
                );
                return;
              }
              FocusManager.instance.primaryFocus?.unfocus();
              OpenFilex.open(path);
            },
      child: SizedBox(
        width: 220,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              message.kind == MessageKind.image
                  ? Icons.image_outlined
                  : Icons.insert_drive_file_outlined,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fileName ?? 'Attachment',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatSize(message.sizeBytes ?? 0),
                    style: TextStyle(color: textColor.withValues(alpha: .7)),
                  ),
                  if (message.transferStatus == TransferStatus.sending ||
                      message.transferStatus == TransferStatus.receiving)
                    LinearProgressIndicator(value: message.transferProgress),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isAllowedToOpen(String path, String? mimeType) {
    // The extension allowlist is the type gate; MIME is sender-supplied metadata
    // and is only checked for consistency with that trusted extension.
    const mimeTypesByExtension = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.heic': 'image/heic',
      '.heif': 'image/heif',
      '.pdf': 'application/pdf',
      '.txt': 'text/plain',
    };
    final fileName = File(path).uri.pathSegments.last;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return false;
    final expectedMimeType =
        mimeTypesByExtension[fileName.substring(dot).toLowerCase()];
    return expectedMimeType != null &&
        mimeType?.toLowerCase().trim() == expectedMimeType;
  }

  String _formatSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Widget _buildStatusIcon(MessageStatus status, Color color) =>
      switch (status) {
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
