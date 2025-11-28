import 'package:cryptic_app/data/network/protocol/client_messages.dart';
import 'package:cryptic_app/data/network/websocket/message_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageQueue', () {
    late MessageQueue queue;

    setUp(() {
      queue = MessageQueue(
        maxSize: 5,
        maxAge: const Duration(hours: 1),
      );
    });

    group('enqueue', () {
      test('should add message to queue', () {
        final message = ListUsersMessage();

        queue.enqueue(message);

        expect(queue.length, 1);
        expect(queue.isEmpty, false);
        expect(queue.isNotEmpty, true);
      });

      test('should add multiple messages', () {
        queue.enqueue(ListUsersMessage());
        queue.enqueue(GetKeyBundleMessage(username: 'bob'));
        queue.enqueue(ListUsersMessage());

        expect(queue.length, 3);
      });

      test('should remove oldest when at capacity', () {
        // Fill queue to capacity
        for (var i = 0; i < 5; i++) {
          queue.enqueue(GetKeyBundleMessage(username: 'user$i'));
        }
        expect(queue.length, 5);
        expect(queue.isFull, true);

        // Add one more
        queue.enqueue(GetKeyBundleMessage(username: 'user5'));

        // Should still be at capacity
        expect(queue.length, 5);

        // First message should be 'user1' not 'user0'
        final first = queue.dequeue() as GetKeyBundleMessage;
        expect(first.username, 'user1');
      });
    });

    group('dequeue', () {
      test('should return null for empty queue', () {
        expect(queue.dequeue(), isNull);
      });

      test('should return oldest message (FIFO)', () {
        queue.enqueue(GetKeyBundleMessage(username: 'first'));
        queue.enqueue(GetKeyBundleMessage(username: 'second'));
        queue.enqueue(GetKeyBundleMessage(username: 'third'));

        final first = queue.dequeue() as GetKeyBundleMessage;
        final second = queue.dequeue() as GetKeyBundleMessage;
        final third = queue.dequeue() as GetKeyBundleMessage;

        expect(first.username, 'first');
        expect(second.username, 'second');
        expect(third.username, 'third');
        expect(queue.isEmpty, true);
      });
    });

    group('dequeueAll', () {
      test('should return empty list for empty queue', () {
        expect(queue.dequeueAll(), isEmpty);
      });

      test('should return all messages in FIFO order', () {
        queue.enqueue(GetKeyBundleMessage(username: 'a'));
        queue.enqueue(GetKeyBundleMessage(username: 'b'));
        queue.enqueue(GetKeyBundleMessage(username: 'c'));

        final messages = queue.dequeueAll();

        expect(messages.length, 3);
        expect((messages[0] as GetKeyBundleMessage).username, 'a');
        expect((messages[1] as GetKeyBundleMessage).username, 'b');
        expect((messages[2] as GetKeyBundleMessage).username, 'c');
        expect(queue.isEmpty, true);
      });
    });

    group('peek', () {
      test('should return null for empty queue', () {
        expect(queue.peek(), isNull);
      });

      test('should return oldest without removing', () {
        queue.enqueue(GetKeyBundleMessage(username: 'first'));
        queue.enqueue(GetKeyBundleMessage(username: 'second'));

        final peeked = queue.peek() as GetKeyBundleMessage;

        expect(peeked.username, 'first');
        expect(queue.length, 2); // Not removed
      });
    });

    group('clear', () {
      test('should remove all messages', () {
        queue.enqueue(ListUsersMessage());
        queue.enqueue(ListUsersMessage());
        queue.enqueue(ListUsersMessage());

        queue.clear();

        expect(queue.isEmpty, true);
        expect(queue.length, 0);
      });
    });

    group('expiration', () {
      test('should skip expired messages on dequeue', () async {
        // Create queue with very short expiration
        final shortQueue = MessageQueue(
          maxSize: 10,
          maxAge: const Duration(milliseconds: 50),
        );

        shortQueue.enqueue(GetKeyBundleMessage(username: 'old'));

        // Wait for expiration
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Add new message
        shortQueue.enqueue(GetKeyBundleMessage(username: 'new'));

        // Old message should be expired
        final message = shortQueue.dequeue() as GetKeyBundleMessage;
        expect(message.username, 'new');
      });
    });

    group('stats', () {
      test('should return correct statistics', () {
        queue.enqueue(ListUsersMessage());
        queue.enqueue(ListUsersMessage());
        queue.enqueue(ListUsersMessage());

        final stats = queue.stats;

        expect(stats.length, 3);
        expect(stats.maxSize, 5);
        expect(stats.isFull, false);
        expect(stats.oldestAge, isNotNull);
      });

      test('should report full when at capacity', () {
        for (var i = 0; i < 5; i++) {
          queue.enqueue(ListUsersMessage());
        }

        expect(queue.stats.isFull, true);
      });
    });

    group('oldestMessageAge', () {
      test('should return null for empty queue', () {
        expect(queue.oldestMessageAge, isNull);
      });

      test('should return age of oldest message', () async {
        queue.enqueue(ListUsersMessage());

        await Future<void>.delayed(const Duration(milliseconds: 50));

        final age = queue.oldestMessageAge;

        expect(age, isNotNull);
        expect(age!.inMilliseconds, greaterThanOrEqualTo(50));
      });
    });
  });

  group('QueueStats', () {
    test('should format toString correctly', () {
      const stats = QueueStats(
        length: 5,
        maxSize: 10,
        oldestAge: Duration(seconds: 30),
        isFull: false,
      );

      final str = stats.toString();

      expect(str, contains('5/10'));
      expect(str, contains('30s'));
      expect(str, contains('false'));
    });
  });

  group('PriorityMessageQueue', () {
    late PriorityMessageQueue queue;

    setUp(() {
      queue = PriorityMessageQueue(
        maxSize: 100,
        maxAge: const Duration(hours: 1),
      );
    });

    test('should start empty', () {
      expect(queue.isEmpty, true);
      expect(queue.length, 0);
    });

    test('should enqueue with different priorities', () {
      queue.enqueue(
        GetKeyBundleMessage(username: 'normal'),
        priority: MessagePriority.normal,
      );
      queue.enqueue(
        GetKeyBundleMessage(username: 'high'),
        priority: MessagePriority.high,
      );
      queue.enqueue(
        GetKeyBundleMessage(username: 'low'),
        priority: MessagePriority.low,
      );

      expect(queue.length, 3);
      expect(queue.isEmpty, false);
    });

    test('should dequeue in priority order', () {
      // Add in mixed order
      queue.enqueue(
        GetKeyBundleMessage(username: 'low'),
        priority: MessagePriority.low,
      );
      queue.enqueue(
        GetKeyBundleMessage(username: 'high'),
        priority: MessagePriority.high,
      );
      queue.enqueue(
        GetKeyBundleMessage(username: 'normal'),
        priority: MessagePriority.normal,
      );

      final messages = queue.dequeueAll();

      expect(messages.length, 3);
      // High priority first
      expect((messages[0] as GetKeyBundleMessage).username, 'high');
      // Normal second
      expect((messages[1] as GetKeyBundleMessage).username, 'normal');
      // Low last
      expect((messages[2] as GetKeyBundleMessage).username, 'low');
    });

    test('should clear all queues', () {
      queue.enqueue(ListUsersMessage(), priority: MessagePriority.high);
      queue.enqueue(ListUsersMessage(), priority: MessagePriority.normal);
      queue.enqueue(ListUsersMessage(), priority: MessagePriority.low);

      queue.clear();

      expect(queue.isEmpty, true);
      expect(queue.length, 0);
    });
  });
}
