// lib/data/engine/incoming_event_handler.dart
//
// Shared handler for incoming MessageReceived / FileReceived engine events.
//
// Extracted from the app.dart engineEvents listener so that message handling
// is a single, awaited, ordered pipeline:
//   decrypt (engine) -> persist (repository) -> update UI state -> notify
//
// Persisting BEFORE notifying guarantees that a notification is never shown
// for a message that failed to be stored. Calls are serialized through a
// future chain so overlapping engine events cannot reorder persistence.

import '../../core/utils/event_log.dart';
import '../../core/utils/logger.dart';
import '../../domain/models/message.dart';
import '../services/notification_service.dart';
import '../storage/repositories/message_repository.dart';
import 'engine_state.dart';

/// Function that adds a persisted message to the conversation state
/// (wired to ConversationsNotifier.addMessage by the caller).
typedef AddMessageFn = void Function(String peerUsername, ChatMessage message);

/// Serial processing chain so events are handled strictly in arrival order.
Future<void> _eventChain = Future.value();

/// Result flags for a single handled event, useful for tests.
class IncomingEventResult {
  const IncomingEventResult({
    required this.kind,
    required this.persisted,
    required this.notified,
    this.suppressionReason,
  });

  final String kind; // 'message' | 'file'
  final bool persisted;
  final bool notified;

  /// Why no notification was posted (null when one was posted).
  final String? suppressionReason;
}

/// Handle a single incoming engine event.
///
/// - [repo]: message repository; when null the event is logged and dropped
///   (message database not open).
/// - [addMessage]: updates the in-memory conversation state.
/// - [notificationService]: notification sink (injectable for tests).
Future<IncomingEventResult> handleIncomingEvent(
  EngineEvent event, {
  required MessageRepository? repo,
  required AddMessageFn addMessage,
  NotificationService? notificationService,
}) {
  // Chain each event behind the previous one to preserve ordering.
  final result = _eventChain.then(
    (_) async => _handle(
      event,
      repo: repo,
      addMessage: addMessage,
      notificationService: notificationService,
    ),
  );
  // Never poison the chain for later events.
  _eventChain = result.catchError(
    (Object e, StackTrace st) {
      // Log swallowed errors: the catch-all must keep the chain alive, but
      // failures still need to surface in the log for diagnostics.
      AppLogger.error(
        'Incoming event handler failed',
        tag: 'IncomingEvents',
        error: e,
        stackTrace: st,
      );
      return IncomingEventResult(
        kind: 'error',
        persisted: false,
        notified: false,
        suppressionReason: 'handler failed: $e',
      );
    },
  );
  return result;
}

Future<IncomingEventResult> _handle(
  EngineEvent event, {
  required MessageRepository? repo,
  required AddMessageFn addMessage,
  NotificationService? notificationService,
}) async {
  if (event is MessageReceived) {
    return _handleMessage(event,
        repo: repo, addMessage: addMessage, notifications: notificationService);
  } else if (event is FileReceived) {
    return _handleFile(event,
        repo: repo, addMessage: addMessage, notifications: notificationService);
  }
  return IncomingEventResult(
      kind: 'ignored', persisted: false, notified: false,
      suppressionReason: 'not an incoming event');
}

Future<IncomingEventResult> _handleMessage(
  MessageReceived event, {
  required MessageRepository? repo,
  required AddMessageFn addMessage,
  required NotificationService? notifications,
}) async {
  final effectiveRepo = repo;
  EventLog.add(
    'UI',
    'message from ${event.fromUser} id=${event.messageId} '
        '${effectiveRepo == null ? 'DROPPED: message database not open' : 'stored'}',
  );
  if (effectiveRepo == null) {
    return IncomingEventResult(
        kind: 'message', persisted: false, notified: false,
        suppressionReason: 'message database not open');
  }

  final msg = ChatMessage(
    id: event.messageId.isNotEmpty
        ? event.messageId
        : DateTime.now().microsecondsSinceEpoch.toString(),
    conversationId: event.fromUser,
    senderId: event.fromUser,
    content: event.plaintext,
    timestamp: event.timestamp,
    direction: MessageDirection.incoming,
    status: MessageStatus.delivered,
  );

  // Persist FIRST, then update state and notify.
  await effectiveRepo.saveIncomingMessage(msg);
  addMessage(event.fromUser, msg);
  final notified = await _notify(notifications, event.fromUser, event.plaintext);
  return IncomingEventResult(
      kind: 'message', persisted: true, notified: notified,
      suppressionReason: notified ? null : 'suppressed');
}

Future<IncomingEventResult> _handleFile(
  FileReceived event, {
  required MessageRepository? repo,
  required AddMessageFn addMessage,
  required NotificationService? notifications,
}) async {
  final effectiveRepo = repo;
  EventLog.add(
    'UI',
    'file ${event.fileId} from ${event.fromUser} '
        '${effectiveRepo == null ? 'DROPPED: message database not open' : 'stored'}',
  );
  if (effectiveRepo == null) {
    return IncomingEventResult(
        kind: 'file', persisted: false, notified: false,
        suppressionReason: 'message database not open');
  }

  final message = ChatMessage(
    id: event.fileId,
    fileId: event.fileId,
    conversationId: event.fromUser,
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

  // Persist FIRST, then update state and notify.
  await effectiveRepo.saveIncomingMessage(message);
  addMessage(event.fromUser, message);
  final notified = await _notify(
      notifications, event.fromUser, 'Attachment: ${event.fileName}');
  return IncomingEventResult(
      kind: 'file', persisted: true, notified: notified,
      suppressionReason: notified ? null : 'suppressed');
}

Future<bool> _notify(
    NotificationService? notifications, String fromUser, String body) async {
  if (notifications == null) return false;
  // Consult the shared suppression predicate BEFORE calling the service so
  // the decision is observable/testable at the handler level (the service
  // re-checks internally as defense in depth).
  if (NotificationService.isSuppressed(fromUser)) return false;
  try {
    await notifications.showMessageNotification(
        fromUser: fromUser, messageBody: body);
    return true;
  } catch (error, stackTrace) {
    AppLogger.warning(
      'Failed to show incoming message notification',
      tag: 'IncomingEventHandler',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}
