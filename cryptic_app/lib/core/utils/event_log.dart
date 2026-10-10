// lib/core/utils/event_log.dart
//
// In-app event log for diagnosing protocol problems on a device.
//
// Keeps the most recent entries in memory only. Entries never contain key
// material, ciphertext or plaintext: wire frames are summarised with
// [summarizeFrame], which shows routing fields and sizes only.

import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One line in the [EventLog].
class EventLogEntry {
  /// Creates an entry.
  const EventLogEntry(this.time, this.category, this.text);

  /// When the entry was recorded.
  final DateTime time;

  /// Short source tag, for example `RX`, `TX`, `ENGINE` or `UI`.
  final String category;

  /// Human readable text.
  final String text;

  @override
  String toString() {
    final t = time.toIso8601String().substring(11, 23);
    return '$t $category $text';
  }
}

/// Process-wide ring buffer of [EventLogEntry] items.
class EventLog extends ChangeNotifier {
  EventLog._();

  /// The shared instance.
  static final EventLog instance = EventLog._();

  /// Maximum number of kept entries. Older entries are dropped.
  static const int maxEntries = 500;

  final Queue<EventLogEntry> _entries = Queue<EventLogEntry>();

  /// Entries, oldest first.
  List<EventLogEntry> get entries => List.unmodifiable(_entries);

  /// Records an entry.
  static void add(String category, String text) =>
      instance._add(category, text);

  void _add(String category, String text) {
    _entries.addLast(EventLogEntry(DateTime.now(), category, text));
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  /// Removes all entries.
  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// All entries as plain text, one per line.
  String asText() => _entries.map((e) => e.toString()).join('\n');
}

/// Keys whose string values are safe to show as they are.
const _safeKeys = {
  'type',
  'message_type',
  'from',
  'to',
  'username',
  'user',
  'message_id',
  'operation',
  'message',
  'status',
  'users',
  'success',
};

/// Summarises a wire frame without secrets.
///
/// Routing fields are shown. Other strings, such as keys, ciphertext and
/// nonces, are replaced by their length. Lists are replaced by their size.
String summarizeFrame(String json) {
  try {
    final decoded = jsonDecode(json);
    return _summarize(decoded, null);
  } catch (_) {
    return 'unparseable frame, ${json.length} chars';
  }
}

String _summarize(Object? value, String? key) {
  if (value is Map) {
    final parts = value.entries
        .map((e) => '${e.key}=${_summarize(e.value, e.key.toString())}')
        .join(' ');
    return '{$parts}';
  }
  if (value is List) {
    if (key == 'users' && value.length <= 20) {
      return '[${value.map((v) => v is String ? v : '?').join(',')}]';
    }
    return '[${value.length}]';
  }
  if (value is String) {
    if (key != null && _safeKeys.contains(key) && value.length <= 80) {
      return value;
    }
    return '<${value.length} chars>';
  }
  return '$value';
}
