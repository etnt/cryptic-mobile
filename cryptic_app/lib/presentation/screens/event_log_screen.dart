/// Event log screen.
///
/// Shows the most recent protocol events seen by the app: frames received
/// from and sent to the server, how the engine handled each incoming message,
/// and what the UI did with it. No keys, ciphertext or message text are shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/event_log.dart';

/// Screen with a live view of the [EventLog].
class EventLogScreen extends StatelessWidget {
  /// Creates the screen.
  const EventLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = EventLog.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: log.asText()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Log copied')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: log.clear,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) {
          // Newest first, so the latest event is visible without scrolling.
          final entries = log.entries.reversed.toList();
          if (entries.isEmpty) {
            return const Center(child: Text('No events yet'));
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) =>
                _EntryTile(entry: entries[index]),
          );
        },
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final EventLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = entry.text.contains('FAILED') ||
        entry.text.contains('DROPPED') ||
        entry.text.contains('failed');
    final color = failed
        ? scheme.error
        : switch (entry.category) {
            'RX' => scheme.primary,
            'TX' => scheme.tertiary,
            _ => scheme.onSurfaceVariant,
          };
    final time = entry.time.toIso8601String().substring(11, 23);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          children: [
            TextSpan(
              text: '$time ',
              style: TextStyle(color: scheme.outline),
            ),
            TextSpan(
              text: '${entry.category.padRight(6)} ',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: entry.text,
              style: TextStyle(color: failed ? scheme.error : null),
            ),
          ],
        ),
      ),
    );
  }
}
