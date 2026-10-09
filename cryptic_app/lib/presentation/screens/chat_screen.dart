/// Chat screen.
///
/// Displays messages for a single conversation with input.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/logger.dart';
import '../../data/engine/engine_state.dart';
import '../../data/engine/payload_codec.dart';
import '../../data/services/incoming_share_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/storage/media_store.dart';
import '../../domain/models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/engine_provider.dart';
import '../providers/incoming_share_provider.dart';
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
    this.takeSharedFiles = false,
    super.key,
  });

  /// The peer's ID (username).
  final String peerId;

  /// When true, this screen takes the pending shares and sends them to
  /// [peerId] when it opens.
  final bool takeSharedFiles;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final ImagePicker _imagePicker = ImagePicker();
  final MediaStore _mediaStore = MediaStore();
  final Set<String> _selectedIds = {};
  // Shares taken from the provider. This screen owns and deletes them.
  List<IncomingShare> _pendingShares = const [];

  bool get _selecting => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.activeChatPeer = widget.peerId;
    _loadHistory();
    if (widget.takeSharedFiles) {
      // Taken once this screen is mounted, not when the peer is picked, so
      // the provider keeps the shares until then. Riverpod does not allow
      // changing a provider during initState, hence the post-frame callback.
      WidgetsBinding.instance.addPostFrameCallback((_) => _takeShares());
    }
  }

  /// Takes ownership of the pending shares and sends them. If this screen was
  /// closed first, the shares stay in the provider.
  void _takeShares() {
    if (!mounted) return;
    _pendingShares = ref.read(incomingShareProvider.notifier).consume();
    unawaited(_sendInitialShares());
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

  /// Remove a failed outgoing attachment from the chat, database and disk.
  Future<void> _discardAttachment(String fileId) async {
    final matching = _messages.where((m) => m.fileId == fileId).toList();
    if (matching.isEmpty) return;
    await _deleteMessages(matching);
  }

  /// Delete messages from the list, the database and local media storage.
  Future<void> _deleteMessages(List<ChatMessage> targets) async {
    if (targets.isEmpty) return;
    final ids = targets.map((m) => m.id).toSet();
    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => ids.contains(m.id));
        _selectedIds.removeAll(ids);
      });
    }
    ref.read(conversationsProvider.notifier).setLastMessage(
          widget.peerId,
          _messages.isEmpty ? null : _messages.last,
        );
    try {
      await ref.read(messageRepositoryProvider)?.deleteMessages(ids);
    } catch (error) {
      AppLogger.warning(
        'Could not delete messages from database',
        tag: 'ChatScreen',
        error: error,
      );
    }
    for (final path in targets.map((m) => m.localPath).whereType<String>()) {
      try {
        await _mediaStore.delete(path);
      } catch (error) {
        AppLogger.warning(
          'Could not delete media file',
          tag: 'ChatScreen',
          error: error,
        );
      }
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  Future<void> _confirmDeleteSelected() async {
    final targets =
        _messages.where((m) => _selectedIds.contains(m.id)).toList();
    if (targets.isEmpty) return;
    final count = targets.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(count == 1 ? 'Delete message?' : 'Delete $count messages?'),
        content: const Text(
          'This removes them from this device only. '
          'The other person keeps their copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _deleteMessages(targets);
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
    if (source == AttachmentSource.file) {
      final selection = await FilePicker.platform.pickFiles();
      if (selection == null || selection.files.isEmpty) return;
      final selectedFile = selection.files.single;
      final path = selectedFile.path;
      if (path == null) {
        _showAttachmentError('Could not read the selected file');
        return;
      }
      try {
        await _sendAttachmentFromFile(path, name: selectedFile.name);
      } finally {
        // file_picker usually returns a copy in the app cache, so the copy
        // is deleted after the send attempt, as the image picker's copy is.
        // A path outside the cache is the user's original file, which is
        // never deleted.
        if (await _isInAppCache(path)) {
          await _deleteTempFile(path);
        }
      }
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: source == AttachmentSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 2048,
    );
    if (picked == null) return;
    try {
      await _sendAttachmentFromFile(picked.path, name: picked.name);
    } finally {
      await _deleteTempFile(picked.path);
    }
  }

  /// Reads, encrypts and sends the file at [path].
  ///
  /// Errors are shown to the user and do not propagate. The caller decides
  /// what to do with [path] afterwards.
  Future<void> _sendAttachmentFromFile(String path, {String? name}) async {
    final fileName = name ?? path.split(RegExp(r'[\\/]')).last;
    String? createdFileId;
    try {
      final file = File(path);
      // Check the size before reading, so large files are never loaded.
      final size = await file.length();
      if (size > AttachmentLimits.maxFileBytes) {
        throw _TooLargeFile(fileName, size);
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('Could not read the selected file');
      }
      if (bytes.length > AttachmentLimits.maxFileBytes) {
        throw _TooLargeFile(fileName, bytes.length);
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
        // A failed outgoing attachment is not shown in the chat.
        unawaited(_discardAttachment(createdFileId));
      }
      _showAttachmentError(
        error is _TooLargeFile
            ? _notSentTooLarge([_describeSize(error.name, error.bytes)])
            : 'Could not send attachment: $error',
      );
    }
  }

  /// Sends the shares taken by this screen, one after another.
  ///
  /// Each copy is deleted after its attempt, including a failed attempt or
  /// an attempt after this screen has closed. Files over the size limit are
  /// skipped; all skipped files are reported together, by name and size.
  /// Shares that are left over because the user closed the screen mid-loop
  /// are reported through a notice that survives the screen.
  Future<void> _sendInitialShares() async {
    final skipped = <String>[];
    var leftOver = 0;
    // The app-level messenger outlives this screen, so a notice can still
    // be shown after the user leaves mid-loop.
    final messenger = mounted ? ScaffoldMessenger.maybeOf(context) : null;
    for (final share in _pendingShares) {
      try {
        if (!mounted) {
          leftOver++;
          continue;
        }
        final size = await _fileSize(share.path);
        if (size != null && size > AttachmentLimits.maxFileBytes) {
          skipped.add(_describeSize(share.fileName, size));
        } else {
          await _sendAttachmentFromFile(share.path, name: share.fileName);
        }
      } finally {
        // Plaintext copies must not stay in the cache.
        await share.deleteCopies();
      }
    }
    if (skipped.isNotEmpty) _showAttachmentError(_notSentTooLarge(skipped));
    if (leftOver > 0) {
      try {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Some files were not sent')),
        );
      } catch (error) {
        // No scaffold can present the notice (e.g. the app is shutting
        // down); at least the fact is logged.
        AppLogger.warning(
          'Some shared files were not sent',
          tag: 'ChatScreen',
          error: error,
        );
      }
    }
  }

  Future<int?> _fileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  /// True when [path] lies inside the app's cache or temporary directory,
  /// i.e. it is a copy a picker made, not the user's original file.
  Future<bool> _isInAppCache(String path) async {
    try {
      final temporaryDir = await getTemporaryDirectory();
      if (_isInside(path, temporaryDir.path)) return true;
      final cacheDir = await getApplicationCacheDirectory();
      return _isInside(path, cacheDir.path);
    } catch (error) {
      AppLogger.warning(
        'Could not resolve the app cache directory',
        tag: 'ChatScreen',
        error: error,
      );
      return false;
    }
  }

  bool _isInside(String path, String directory) => path.startsWith(
        directory.endsWith(Platform.pathSeparator)
            ? directory
            : '$directory${Platform.pathSeparator}',
      );

  Future<void> _deleteTempFile(String path) async {
    try {
      final tempFile = File(path);
      // Async on purpose: large attachments must not block the UI isolate.
      // ignore: avoid_slow_async_io
      if (await tempFile.exists()) await tempFile.delete();
    } catch (error) {
      AppLogger.warning(
        'Could not delete temporary attachment file',
        tag: 'ChatScreen',
        error: error,
      );
    }
  }

  /// Text for a file that is too large to send, e.g. `video.mp4 (25.3 MB)`.
  String _describeSize(String name, int bytes) {
    return '$name (${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB)';
  }

  /// The message for one or more files that were not sent because of size.
  String _notSentTooLarge(List<String> entries) {
    final limit = AttachmentLimits.maxFileBytes ~/ (1024 * 1024);
    return 'Not sent, over the $limit MB limit: ${entries.join(', ')}';
  }

  void _showAttachmentError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
        } else if (event is FileSendProgress &&
            event.toUser == widget.peerId &&
            event.failed) {
          unawaited(_discardAttachment(event.fileId));
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

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) setState(_selectedIds.clear);
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selectedIds.clear),
                ),
                title: Text('${_selectedIds.length} selected'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: _confirmDeleteSelected,
                  ),
                ],
              )
            : AppBar(
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
                              selected: _selectedIds.contains(message.id),
                              selectionMode: _selecting,
                              onTap: () => _toggleSelection(message.id),
                              onLongPress: () => _toggleSelection(message.id),
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

/// Thrown when a file is over [AttachmentLimits.maxFileBytes].
class _TooLargeFile implements Exception {
  const _TooLargeFile(this.name, this.bytes);

  final String name;
  final int bytes;

  @override
  String toString() => 'File too large: $name (${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB)';
}
