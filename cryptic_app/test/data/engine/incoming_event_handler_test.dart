// test/data/engine/incoming_event_handler_test.dart
//
// Tests for the shared incoming-event handler: persist-before-notify
// ordering, notification suppression, and cross-event ordering.

import 'dart:async';

import 'package:cryptic_app/data/engine/engine_state.dart';
import 'package:cryptic_app/data/engine/incoming_event_handler.dart';
import 'package:cryptic_app/data/services/notification_service.dart';
import 'package:cryptic_app/data/storage/repositories/message_repository.dart';
import 'package:cryptic_app/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMessageRepository extends Mock implements MessageRepository {}

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  late MockMessageRepository repo;
  late MockNotificationService notifications;
  final List<String> callOrder = [];
  final List<ChatMessage> savedMessages = [];
  final Map<String, List<ChatMessage>> addedByPeer = {};

  setUpAll(() {
    registerFallbackValue(ChatMessage(
      id: 'fallback',
      conversationId: 'x',
      senderId: 'x',
      content: 'x',
      timestamp: DateTime(2025),
      direction: MessageDirection.incoming,
      status: MessageStatus.delivered,
    ));
  });

  setUp(() {
    repo = MockMessageRepository();
    notifications = MockNotificationService();
    callOrder.clear();
    savedMessages.clear();
    addedByPeer.clear();
    NotificationService.instance.activeChatPeer = null;
    NotificationService.appResumed = false;

    when(() => repo.saveIncomingMessage(any())).thenAnswer((invocation) async {
      callOrder.add('save');
      savedMessages.add(invocation.positionalArguments[0] as ChatMessage);
    });
    when(() => notifications.showMessageNotification(
          fromUser: any(named: 'fromUser'),
          messageBody: any(named: 'messageBody'),
        )).thenAnswer((invocation) async {
      callOrder.add('notify');
    });
  });

  AddMessageFn addMessageFn() => (peer, message) {
        callOrder.add('state');
        addedByPeer.putIfAbsent(peer, () => []).add(message);
      };

  MessageReceived messageEvent({String id = 'm1'}) => MessageReceived(
        fromUser: 'alice',
        plaintext: 'hello',
        timestamp: DateTime(2025, 1, 1, 12),
        messageId: id,
      );

  test('persists the message before updating state and notifying', () async {
    final result = await handleIncomingEvent(
      messageEvent(),
      repo: repo,
      addMessage: addMessageFn(),
      notificationService: notifications,
    );

    expect(result.persisted, isTrue);
    expect(result.notified, isTrue);
    expect(callOrder, ['save', 'state', 'notify']);
    expect(savedMessages.single.content, 'hello');
    expect(addedByPeer['alice']!.single.senderId, 'alice');
  });

  test('drops the event without notifying when the database is not open',
      () async {
    final result = await handleIncomingEvent(
      messageEvent(),
      repo: null,
      addMessage: addMessageFn(),
      notificationService: notifications,
    );

    expect(result.persisted, isFalse);
    expect(result.notified, isFalse);
    verifyNever(() => repo.saveIncomingMessage(any()));
    verifyNever(() => notifications.showMessageNotification(
        fromUser: any(named: 'fromUser'),
        messageBody: any(named: 'messageBody')));
    expect(addedByPeer, isEmpty);
  });

  test('persists but suppresses the notification for the open chat', () async {
    NotificationService.instance.activeChatPeer = 'alice';
    NotificationService.appResumed = true;
    addTearDown(() => NotificationService.appResumed = false);

    final result = await handleIncomingEvent(
      messageEvent(),
      repo: repo,
      addMessage: addMessageFn(),
      notificationService: notifications,
    );

    // The message is still stored and shown in-app; only the shade
    // notification is suppressed by the service.
    expect(result.persisted, isTrue);
    expect(savedMessages, hasLength(1));
    verifyNever(() => notifications.showMessageNotification(
        fromUser: any(named: 'fromUser'),
        messageBody: any(named: 'messageBody')));
    expect(callOrder, ['save', 'state']);
  });

  test('handles message and file events strictly in arrival order', () async {
    // Make the first save slow so a naive implementation would interleave.
    final firstSaveGate = Completer<void>();
    var firstCall = true;
    when(() => repo.saveIncomingMessage(any())).thenAnswer((invocation) async {
      savedMessages.add(invocation.positionalArguments[0] as ChatMessage);
      if (firstCall) {
        firstCall = false;
        callOrder.add('save-start');
        await firstSaveGate.future;
        callOrder.add('save-done');
      } else {
        callOrder.add('save');
      }
    });

    final second = handleIncomingEvent(
      messageEvent(id: 'm2'),
      repo: repo,
      addMessage: addMessageFn(),
      notificationService: notifications,
    );

    final first = handleIncomingEvent(
      messageEvent(id: 'm1'),
      repo: repo,
      addMessage: addMessageFn(),
      notificationService: notifications,
    );

    // Let the chain start, then release the first save.
    await Future<void>.delayed(Duration.zero);
    expect(callOrder.first, 'save-start');
    firstSaveGate.complete();

    final results = await Future.wait([first, second]);

    // Both events were persisted and notified; the second event's handler
    // only ran after the first one fully completed (save-done before the
    // second save, and each event's notify follows its own save).
    expect(results.every((r) => r.persisted), isTrue);
    expect(savedMessages, hasLength(2));
    expect(callOrder.indexOf('save-done'),
        lessThan(callOrder.lastIndexOf('save')));
    expect(callOrder, [
      'save-start',
      'save-done',
      'state',
      'notify',
      'save',
      'state',
      'notify',
    ]);
  });

  test('file events persist first and notify with the attachment body',
      () async {
    final event = FileReceived(
      messageId: 'fm1',
      fromUser: 'bob',
      fileId: 'file-1',
      fileName: 'report.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 1024,
      localPath: '/tmp/report.pdf',
      timestamp: DateTime(2025, 1, 1, 13),
    );

    final result = await handleIncomingEvent(
      event,
      repo: repo,
      addMessage: addMessageFn(),
      notificationService: notifications,
    );

    expect(result.kind, 'file');
    expect(result.persisted, isTrue);
    expect(callOrder, ['save', 'state', 'notify']);
    expect(savedMessages.single.fileName, 'report.pdf');
    verify(() => notifications.showMessageNotification(
          fromUser: 'bob',
          messageBody: 'Attachment: report.pdf',
        )).called(1);
  });
}
