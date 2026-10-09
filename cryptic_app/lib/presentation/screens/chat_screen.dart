/// Chat screen.
///
/// Displays messages for a single conversation with input.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/external_activity_guard.dart';
import '../../core/utils/logger.dart';
import '../../data/engine/engine_state.dart';
import '../../data/engine/payload_codec.dart';
import '../../data/services/notification_service.dart';
import '../../data/storage/media_store.dart';
import '../../domain/models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/engine_provider.dart';
import '../providers/messages_provider.dart';
import '../widgets/attachment_sheet.dart';
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
  final ImagePicker _imagePicker = ImagePicker();
  final MediaStore _mediaStore = MediaStore();

  @override
  void initState() {
    super.initState();
    NotificationService.instance.activeChatPeer = widget.peerId;
    _loadHistory();
  }

  @override
  void dispose() {
    NotificationService.instance.activeChatPeer = null;
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
      id: event.messageId.isNotEmpty
          ? event.messageId
          : DateTime.now().microsecondsSinceEpoch.toString(),
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

    // Persistence and conversation updates are handled globally by
    // the listener in app.dart, so we only update the local UI here.

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _addIncomingFile(FileReceived event) {
    final message = ChatMessage(
      id: event.fileId,
      fileId: event.fileId,
      conversationId: widget.peerId,
      senderId: event.fromUser,
      content: event.fileName,
      timestamp: event.timestamp,
      direction: MessageDirection.incoming,
      status: MessageStatus.delivered,
      kind: event.mimeType.startsWith('image/')
          ? MessageKind.image
          : MessageKind.file,
      fileName: event.fileName,
      mimeType: event.mimeType,
      sizeBytes: event.sizeBytes,
      localPath: event.localPath,
      transferProgress: 1,
      transferStatus: TransferStatus.complete,
    );
    _upsertLocalMessage(message);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _handleFileProgress(FileReceiveProgress event) {
    final matching = _messages.where((message) => message.id == event.fileId);
    final message = matching.isEmpty
        ? ChatMessage(
            id: event.fileId,
            fileId: event.fileId,
            conversationId: widget.peerId,
            senderId: event.fromUser,
            content: event.fileName,
            timestamp: DateTime.now(),
            direction: MessageDirection.incoming,
            kind: event.mimeType.startsWith('image/')
                ? MessageKind.image
                : MessageKind.file,
            fileName: event.fileName,
            mimeType: event.mimeType,
            sizeBytes: event.sizeBytes,
            transferProgress: event.progress,
            transferStatus:
                event.failed ? TransferStatus.failed : TransferStatus.receiving,
            status: event.failed ? MessageStatus.failed : MessageStatus.sending,
          )
        : matching.first.copyWith(
            transferProgress: event.progress,
            transferStatus:
                event.failed ? TransferStatus.failed : TransferStatus.receiving,
            status: event.failed ? MessageStatus.failed : null,
          );
    _upsertLocalMessage(message);
  }

  void _upsertLocalMessage(ChatMessage message) {
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index < 0) {
        _messages.add(message);
      } else {
        _messages[index] = message;
      }
    });
  }

  void _updateAttachmentProgress({
    required String fileId,
    required double progress,
    required TransferStatus status,
  }) {
    final index = _messages.indexWhere((message) => message.fileId == fileId);
    if (index < 0) return;
    final updated = _messages[index].copyWith(
      transferProgress: progress,
      transferStatus: status,
      status: status == TransferStatus.complete
          ? MessageStatus.sent
          : status == TransferStatus.failed
              ? MessageStatus.failed
              : _messages[index].status,
    );
    _upsertLocalMessage(updated);
    ref.read(conversationsProvider.notifier).updateAttachmentMessage(
          widget.peerId,
          updated.id,
          progress: progress,
          transferStatus: status,
          status: updated.status,
        );
    if (status == TransferStatus.complete || status == TransferStatus.failed) {
      unawaited(ref.read(messageRepositoryProvider)?.saveMessage(updated));
    }
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
    unawaited(ref.read(messageRepositoryProvider)?.saveMessage(message));

    // Add to conversation (for last message display)
    ref.read(conversationsProvider.notifier).addMessage(widget.peerId, message);

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Send via engine
    final engine = ref.read(engineProvider);
    if (engine == null) {
      AppLogger.error(
        'Cannot send message because the engine is unavailable',
        tag: 'ChatScreen',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Send failed: engine not available'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    AppLogger.debug(
      'Sending message to ${widget.peerId} '
      '(connected=${engine.isConnected})',
      tag: 'ChatScreen',
    );
    try {
      await engine.sendMessage(widget.peerId, text);
      AppLogger.debug('Message sent successfully', tag: 'ChatScreen');
    } catch (e, stack) {
      AppLogger.error(
        'Error sending message',
        tag: 'ChatScreen',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openAttachmentSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => AttachmentSheet(onSelected: _sendAttachment),
    );
  }

  Future<void> _sendAttachment(AttachmentSource source) async {
    String? createdFileId;
    try {
      Uint8List? bytes;
      String fileName;
      if (source == AttachmentSource.file) {
        final selection = await ExternalActivityGuard.run(
          () => FilePicker.platform.pickFiles(),
        );
        if (selection == null || selection.files.isEmpty) return;
        final selectedFile = selection.files.single;
        if (selectedFile.size > AttachmentLimits.maxFileBytes) {
          throw StateError('Files must be 10 MB or smaller');
        }
        fileName = selectedFile.name;
        final path = selectedFile.path;
        bytes =
            path == null ? selectedFile.bytes : await File(path).readAsBytes();
      } else {
        final picked = await ExternalActivityGuard.run(
          () => _imagePicker.pickImage(
            source: source == AttachmentSource.camera
                ? ImageSource.camera
                : ImageSource.gallery,
            imageQuality: 80,
            maxWidth: 2048,
          ),
        );
        if (picked == null) return;
        try {
          if (await picked.length() > AttachmentLimits.maxFileBytes) {
            throw StateError('Files must be 10 MB or smaller');
          }
          bytes = await picked.readAsBytes();
          fileName = picked.name;
        } finally {
          try {
            final tempFile = File(picked.path);
            // Async on purpose: large attachments must not block the UI isolate.
            // ignore: avoid_slow_async_io
            if (await tempFile.exists()) await tempFile.delete();
          } catch (error) {
            AppLogger.warning(
              'Could not delete image-picker temporary file',
              tag: 'ChatScreen',
              error: error,
            );
          }
        }
      }
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Could not read the selected file');
      }
      if (bytes.length > AttachmentLimits.maxFileBytes) {
        throw StateError('Files must be 10 MB or smaller');
      }
      if (!mounted) return;
      final mimeType = lookupMimeType(fileName, headerBytes: bytes) ??
          'application/octet-stream';
      final fileId = const Uuid().v4().replaceAll('-', '');
      createdFileId = fileId;
      final localPath = await _mediaStore.save(
        peer: widget.peerId,
        fileId: fileId,
        fileName: fileName,
        bytes: bytes,
      );
      if (!mounted) return;
      final message = ChatMessage(
        id: fileId,
        fileId: fileId,
        conversationId: widget.peerId,
        senderId: ref.read(authProvider).username ?? 'me',
        content: fileName,
        timestamp: DateTime.now(),
        direction: MessageDirection.outgoing,
        status: MessageStatus.sending,
        kind: mimeType.startsWith('image/')
            ? MessageKind.image
            : MessageKind.file,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        localPath: localPath,
        transferProgress: 0,
        transferStatus: TransferStatus.sending,
      );
      _upsertLocalMessage(message);
      unawaited(ref.read(messageRepositoryProvider)?.saveMessage(message));
      ref
          .read(conversationsProvider.notifier)
          .addMessage(widget.peerId, message);
      final engine = ref.read(engineProvider);
      if (engine == null) throw StateError('Messaging engine is unavailable');
      await engine.sendFile(
        widget.peerId,
        bytes,
        fileName,
        mimeType,
        fileId: fileId,
      );
    } catch (error) {
      if (createdFileId != null) {
        _updateAttachmentProgress(
          fileId: createdFileId,
          progress: 0,
          status: TransferStatus.failed,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send attachment: $error')),
        );
      }
    }
  }

  Future<void> _resetSession() async {
    final engine = ref.read(engineProvider);
    if (engine == null) return;

    AppLogger.info(
      'Resetting session with ${widget.peerId}',
      tag: 'ChatScreen',
    );
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
          _addIncomingMessage(event);
        } else if (event is FileReceived && event.fromUser == widget.peerId) {
          _addIncomingFile(event);
        } else if (event is FileReceiveProgress &&
            event.fromUser == widget.peerId) {
          _handleFileProgress(event);
        } else if (event is FileSendProgress && event.toUser == widget.peerId) {
          _updateAttachmentProgress(
            fileId: event.fileId,
            progress: event.progress,
            status: event.failed
                ? TransferStatus.failed
                : event.progress >= 1
                    ? TransferStatus.complete
                    : TransferStatus.sending,
          );
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
            onAttach: _openAttachmentSheet,
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
