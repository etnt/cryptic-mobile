// Tests for domain models

import 'package:flutter_test/flutter_test.dart';

import 'package:cryptic_app/domain/models/message.dart';
import 'package:cryptic_app/domain/models/conversation.dart';
import 'package:cryptic_app/domain/models/contact.dart';

void main() {
  group('ChatMessage', () {
    final timestamp = DateTime(2025, 11, 30, 12, 0);

    test('should create message with required fields', () {
      final message = ChatMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: 'alice',
        content: 'Hello!',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
      );

      expect(message.id, equals('msg-1'));
      expect(message.conversationId, equals('conv-1'));
      expect(message.senderId, equals('alice'));
      expect(message.content, equals('Hello!'));
      expect(message.timestamp, equals(timestamp));
      expect(message.direction, equals(MessageDirection.outgoing));
      expect(message.status, equals(MessageStatus.sent));
    });

    test('isOutgoing should return correct value', () {
      final outgoing = ChatMessage(
        id: '1',
        conversationId: 'c1',
        senderId: 'me',
        content: 'test',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
      );

      final incoming = ChatMessage(
        id: '2',
        conversationId: 'c1',
        senderId: 'other',
        content: 'test',
        timestamp: timestamp,
        direction: MessageDirection.incoming,
      );

      expect(outgoing.isOutgoing, isTrue);
      expect(incoming.isOutgoing, isFalse);
    });

    test('isFailed should return true for failed status', () {
      final failed = ChatMessage(
        id: '1',
        conversationId: 'c1',
        senderId: 'me',
        content: 'test',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
        status: MessageStatus.failed,
      );

      final sent = ChatMessage(
        id: '2',
        conversationId: 'c1',
        senderId: 'me',
        content: 'test',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
        status: MessageStatus.sent,
      );

      expect(failed.isFailed, isTrue);
      expect(sent.isFailed, isFalse);
    });

    test('isPending should return true for pending/sending status', () {
      final pending = ChatMessage(
        id: '1',
        conversationId: 'c1',
        senderId: 'me',
        content: 'test',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
        status: MessageStatus.pending,
      );

      final sending = ChatMessage(
        id: '2',
        conversationId: 'c1',
        senderId: 'me',
        content: 'test',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
        status: MessageStatus.sending,
      );

      final sent = ChatMessage(
        id: '3',
        conversationId: 'c1',
        senderId: 'me',
        content: 'test',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
        status: MessageStatus.sent,
      );

      expect(pending.isPending, isTrue);
      expect(sending.isPending, isTrue);
      expect(sent.isPending, isFalse);
    });

    test('copyWith should create new instance with updated fields', () {
      final original = ChatMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: 'alice',
        content: 'Hello!',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
        status: MessageStatus.pending,
      );

      final updated = original.copyWith(status: MessageStatus.sent);

      expect(updated.id, equals(original.id));
      expect(updated.status, equals(MessageStatus.sent));
      expect(original.status, equals(MessageStatus.pending));
    });

    test('equality should be based on id', () {
      final msg1 = ChatMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: 'alice',
        content: 'Hello!',
        timestamp: timestamp,
        direction: MessageDirection.outgoing,
      );

      final msg2 = ChatMessage(
        id: 'msg-1',
        conversationId: 'conv-2',
        senderId: 'bob',
        content: 'Different',
        timestamp: timestamp,
        direction: MessageDirection.incoming,
      );

      expect(msg1, equals(msg2));
    });
  });

  group('Conversation', () {
    test('should create conversation with required fields', () {
      const conversation = Conversation(
        id: 'conv-1',
        peerUsername: 'bob',
      );

      expect(conversation.id, equals('conv-1'));
      expect(conversation.peerUsername, equals('bob'));
      expect(conversation.unreadCount, equals(0));
      expect(conversation.hasActiveSession, isFalse);
    });

    test('displayName should use peerDisplayName if set', () {
      const withDisplayName = Conversation(
        id: 'conv-1',
        peerUsername: 'bob123',
        peerDisplayName: 'Bob Smith',
      );

      const withoutDisplayName = Conversation(
        id: 'conv-2',
        peerUsername: 'alice456',
      );

      expect(withDisplayName.displayName, equals('Bob Smith'));
      expect(withoutDisplayName.displayName, equals('alice456'));
    });

    test('hasUnread should return true when unreadCount > 0', () {
      const noUnread = Conversation(
        id: 'conv-1',
        peerUsername: 'bob',
        unreadCount: 0,
      );

      const hasUnread = Conversation(
        id: 'conv-2',
        peerUsername: 'alice',
        unreadCount: 5,
      );

      expect(noUnread.hasUnread, isFalse);
      expect(hasUnread.hasUnread, isTrue);
    });

    test('copyWith should create new instance with updated fields', () {
      const original = Conversation(
        id: 'conv-1',
        peerUsername: 'bob',
        unreadCount: 0,
      );

      final updated = original.copyWith(unreadCount: 3);

      expect(updated.id, equals(original.id));
      expect(updated.unreadCount, equals(3));
      expect(original.unreadCount, equals(0));
    });

    test('equality should be based on id', () {
      const conv1 = Conversation(
        id: 'conv-1',
        peerUsername: 'bob',
      );

      const conv2 = Conversation(
        id: 'conv-1',
        peerUsername: 'alice',
      );

      expect(conv1, equals(conv2));
    });
  });

  group('Contact', () {
    test('should create contact with required fields', () {
      const contact = Contact(
        username: 'alice',
      );

      expect(contact.username, equals('alice'));
      expect(contact.status, equals(ContactStatus.unknown));
      expect(contact.hasSession, isFalse);
      expect(contact.isVerified, isFalse);
    });

    test('name should use displayName if set', () {
      const withDisplayName = Contact(
        username: 'alice123',
        displayName: 'Alice Johnson',
      );

      const withoutDisplayName = Contact(
        username: 'bob456',
      );

      expect(withDisplayName.name, equals('Alice Johnson'));
      expect(withoutDisplayName.name, equals('bob456'));
    });

    test('isOnline should return true when status is online', () {
      const online = Contact(
        username: 'alice',
        status: ContactStatus.online,
      );

      const offline = Contact(
        username: 'bob',
        status: ContactStatus.offline,
      );

      const unknown = Contact(
        username: 'charlie',
        status: ContactStatus.unknown,
      );

      expect(online.isOnline, isTrue);
      expect(offline.isOnline, isFalse);
      expect(unknown.isOnline, isFalse);
    });

    test('copyWith should create new instance with updated fields', () {
      const original = Contact(
        username: 'alice',
        status: ContactStatus.offline,
      );

      final updated = original.copyWith(status: ContactStatus.online);

      expect(updated.username, equals(original.username));
      expect(updated.status, equals(ContactStatus.online));
      expect(original.status, equals(ContactStatus.offline));
    });

    test('equality should be based on username', () {
      const contact1 = Contact(
        username: 'alice',
        displayName: 'Alice',
      );

      const contact2 = Contact(
        username: 'alice',
        displayName: 'Alice Different',
      );

      expect(contact1, equals(contact2));
    });
  });

  group('MessageStatus', () {
    test('should have all expected values', () {
      expect(MessageStatus.values, contains(MessageStatus.pending));
      expect(MessageStatus.values, contains(MessageStatus.sending));
      expect(MessageStatus.values, contains(MessageStatus.sent));
      expect(MessageStatus.values, contains(MessageStatus.delivered));
      expect(MessageStatus.values, contains(MessageStatus.read));
      expect(MessageStatus.values, contains(MessageStatus.failed));
    });
  });

  group('MessageDirection', () {
    test('should have all expected values', () {
      expect(MessageDirection.values, contains(MessageDirection.outgoing));
      expect(MessageDirection.values, contains(MessageDirection.incoming));
    });
  });

  group('ContactStatus', () {
    test('should have all expected values', () {
      expect(ContactStatus.values, contains(ContactStatus.online));
      expect(ContactStatus.values, contains(ContactStatus.offline));
      expect(ContactStatus.values, contains(ContactStatus.unknown));
    });
  });
}
