/// Pending incoming shares.
///
/// Holds files shared from other apps until the user is logged in and has
/// picked a peer. Nothing is sent from here.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../data/services/incoming_share_service.dart';

/// Provider for the share service. Override in tests.
final incomingShareServiceProvider =
    Provider<IncomingShareService>((ref) => IncomingShareService());

/// Notifier holding shares that have not been sent yet.
class IncomingShareNotifier extends StateNotifier<List<IncomingShare>> {
  /// Creates a notifier. Call [start] once the app is running.
  IncomingShareNotifier(this._service) : super(const []);

  final IncomingShareService _service;
  StreamSubscription<List<IncomingShare>>? _subscription;
  bool _started = false;

  /// Starts listening for shares and loads the one that launched the app.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscription = _service.shareStream.listen(
      add,
      onError: (Object error, StackTrace stackTrace) => AppLogger.warning(
        'Incoming share stream failed',
        tag: 'Share',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    try {
      add(await _service.takeInitialShares());
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Could not read the share that launched the app',
        tag: 'Share',
        error: error,
        stackTrace: stackTrace,
      );
    }
    // Pending shares are kept, along with their previews; anything else in
    // the share cache is stale.
    await _service.sweepStaleCopies(
      () => [
        for (final item in state) ...[
          item.path,
          if (item.thumbnailPath != null) item.thumbnailPath!,
        ],
      ],
    );
  }

  /// Adds shares to the pending list.
  void add(List<IncomingShare> shares) {
    if (shares.isEmpty) return;
    state = [...state, ...shares];
  }

  /// Returns the pending shares and clears the list.
  /// The caller now owns the temporary files and must delete them.
  List<IncomingShare> consume() {
    final items = state;
    state = const [];
    return items;
  }

  /// Drops the pending shares and deletes their temporary copies and previews.
  Future<void> discard() async {
    final items = consume();
    for (final item in items) {
      await item.deleteCopies();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// Provider for shares waiting to be sent.
final incomingShareProvider =
    StateNotifierProvider<IncomingShareNotifier, List<IncomingShare>>(
  (ref) => IncomingShareNotifier(ref.watch(incomingShareServiceProvider)),
);
