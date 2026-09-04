/// Message queue for offline message storage.
///
/// Queues outbound messages when disconnected, to be sent
/// when connection is restored.
library;

import 'dart:collection';

import '../protocol/protocol_message.dart';

/// Entry in the message queue.
class QueueEntry {
  /// Creates a queue entry.
  QueueEntry({
    required this.message,
    required this.enqueuedAt,
  });

  /// The queued message.
  final ProtocolMessage message;

  /// When the message was enqueued.
  final DateTime enqueuedAt;

  /// Check if this entry has expired.
  bool isExpired(Duration maxAge) =>
      DateTime.now().difference(enqueuedAt) > maxAge;
}

/// Priority levels for queued messages.
enum MessagePriority {
  /// Normal priority (default).
  normal,

  /// High priority - sent first after reconnection.
  high,

  /// Low priority - sent last after reconnection.
  low,
}

/// Queue for storing messages when disconnected.
///
/// Features:
/// - Maximum size limit with overflow handling
/// - Message expiration based on age
/// - Priority-based ordering
/// - Persistence support (optional)
class MessageQueue {
  /// Creates a message queue.
  MessageQueue({
    this.maxSize = 1000,
    this.maxAge = const Duration(hours: 24),
  });

  /// Maximum number of messages to queue.
  final int maxSize;

  /// Maximum age before messages are discarded.
  final Duration maxAge;

  final Queue<QueueEntry> _queue = Queue();

  /// Number of messages in the queue.
  int get length => _queue.length;

  /// Whether the queue is empty.
  bool get isEmpty => _queue.isEmpty;

  /// Whether the queue is not empty.
  bool get isNotEmpty => _queue.isNotEmpty;

  /// Whether the queue is at capacity.
  bool get isFull => _queue.length >= maxSize;

  /// Add a message to the queue.
  ///
  /// If the queue is full, the oldest message is removed.
  /// Returns true if the message was added successfully.
  bool enqueue(ProtocolMessage message) {
    // Remove oldest if at capacity
    if (isFull && _queue.isNotEmpty) {
      _queue.removeFirst();
    }

    _queue.add(
      QueueEntry(
        message: message,
        enqueuedAt: DateTime.now(),
      ),
    );

    return true;
  }

  /// Remove and return the oldest message.
  ///
  /// Returns null if the queue is empty.
  /// Skips expired messages.
  ProtocolMessage? dequeue() {
    _removeExpired();

    if (_queue.isEmpty) return null;

    final entry = _queue.removeFirst();
    return entry.message;
  }

  /// Remove and return all messages.
  ///
  /// Returns messages in FIFO order.
  /// Skips expired messages.
  List<ProtocolMessage> dequeueAll() {
    _removeExpired();

    final messages = <ProtocolMessage>[];
    while (_queue.isNotEmpty) {
      messages.add(_queue.removeFirst().message);
    }
    return messages;
  }

  /// Peek at the oldest message without removing it.
  ///
  /// Returns null if the queue is empty.
  ProtocolMessage? peek() {
    _removeExpired();

    if (_queue.isEmpty) return null;
    return _queue.first.message;
  }

  /// Clear all messages from the queue.
  void clear() {
    _queue.clear();
  }

  /// Remove expired messages from the queue.
  void _removeExpired() {
    while (_queue.isNotEmpty && _queue.first.isExpired(maxAge)) {
      _queue.removeFirst();
    }
  }

  /// Get the age of the oldest message.
  ///
  /// Returns null if the queue is empty.
  Duration? get oldestMessageAge {
    if (_queue.isEmpty) return null;
    return DateTime.now().difference(_queue.first.enqueuedAt);
  }

  /// Get queue statistics.
  QueueStats get stats => QueueStats(
        length: _queue.length,
        maxSize: maxSize,
        oldestAge: oldestMessageAge,
        isFull: isFull,
      );
}

/// Statistics about the message queue.
class QueueStats {
  /// Creates queue statistics.
  const QueueStats({
    required this.length,
    required this.maxSize,
    required this.isFull,
    this.oldestAge,
  });

  /// Number of messages in queue.
  final int length;

  /// Maximum queue size.
  final int maxSize;

  /// Age of oldest message.
  final Duration? oldestAge;

  /// Whether the queue is full.
  final bool isFull;

  @override
  String toString() => 'QueueStats(length: $length/$maxSize, '
      'oldest: ${oldestAge?.inSeconds ?? 0}s, '
      'full: $isFull)';
}

/// A priority-aware message queue.
///
/// Messages with higher priority are sent first after reconnection.
class PriorityMessageQueue {
  /// Creates a priority message queue.
  PriorityMessageQueue({
    int maxSize = 1000,
    Duration maxAge = const Duration(hours: 24),
  })  : _highQueue = MessageQueue(maxSize: maxSize ~/ 4, maxAge: maxAge),
        _normalQueue = MessageQueue(maxSize: maxSize ~/ 2, maxAge: maxAge),
        _lowQueue = MessageQueue(maxSize: maxSize ~/ 4, maxAge: maxAge);

  final MessageQueue _highQueue;
  final MessageQueue _normalQueue;
  final MessageQueue _lowQueue;

  /// Total number of messages across all queues.
  int get length => _highQueue.length + _normalQueue.length + _lowQueue.length;

  /// Whether all queues are empty.
  bool get isEmpty =>
      _highQueue.isEmpty && _normalQueue.isEmpty && _lowQueue.isEmpty;

  /// Add a message with specified priority.
  void enqueue(ProtocolMessage message,
      {MessagePriority priority = MessagePriority.normal}) {
    final queue = switch (priority) {
      MessagePriority.high => _highQueue,
      MessagePriority.normal => _normalQueue,
      MessagePriority.low => _lowQueue,
    };
    queue.enqueue(message);
  }

  /// Remove and return all messages in priority order.
  List<ProtocolMessage> dequeueAll() => [
        ..._highQueue.dequeueAll(),
        ..._normalQueue.dequeueAll(),
        ..._lowQueue.dequeueAll(),
      ];

  /// Clear all queues.
  void clear() {
    _highQueue.clear();
    _normalQueue.clear();
    _lowQueue.clear();
  }
}
