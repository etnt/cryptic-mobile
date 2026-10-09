/// Incoming share service.
///
/// Wraps `receive_sharing_intent` so the rest of the app only sees
/// [IncomingShare] values for photos, videos and files shared from other apps.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/utils/logger.dart';

/// Native channel that returns the iOS app-group folder used by the share
/// plugin (see `AppDelegate.swift`).
const _shareCacheChannel = MethodChannel('cryptic/share_cache');

/// A file shared into Cryptic from another app.
///
/// [path] is a plaintext temporary copy made by the platform. The copy must
/// be deleted with [deleteCopies] once it is sent or discarded.
class IncomingShare {
  /// Creates a shared item.
  const IncomingShare({
    required this.path,
    required this.mimeType,
    this.thumbnailPath,
  });

  /// Path of the temporary copy on disk.
  final String path;

  /// MIME type, e.g. `image/jpeg`.
  final String mimeType;

  /// Preview image the platform made for a video (on Android `<name>.png`
  /// in the cache directory). Null when there is none.
  final String? thumbnailPath;

  /// File name taken from the temporary path.
  String get fileName => path.split(RegExp(r'[\\/]')).last;

  /// Deletes the plaintext copy and its preview. Errors are logged, not thrown.
  Future<void> deleteCopies() async {
    await _deleteQuietly(path);
    final thumbnail = thumbnailPath;
    if (thumbnail != null) await _deleteQuietly(thumbnail);
  }
}

/// Files kept for this long after their last write are never swept, so a
/// copy that was just written for a share that is still being delivered is
/// not deleted.
const _sweepGracePeriod = Duration(minutes: 5);

/// Fallback names the Android plugin gives a shared copy when the display
/// name is unavailable, e.g. `IMG_1717190000000.jpg` (prefix depends on the
/// MIME type). Video previews are written as `<copy name>.png`, so a preview
/// of a fallback-named copy is `IMG_1717190000000.jpg.png`.
final RegExp _pluginCopyPattern = RegExp(r'^(IMG|VID|FILE)_\d+\.[^.]+$');

/// Thumbnail PNGs of fallback-named copies (see [_pluginCopyPattern]).
/// Arbitrary PNGs written by other apps or the user are never matched.
final RegExp _pluginThumbnailPattern =
    RegExp(r'^(IMG|VID|FILE)_\d+\.[^.]+\.png$');

/// Deletes a file if it exists. Errors are logged, not thrown.
Future<void> _deleteQuietly(String path) async {
  try {
    final file = File(path);
    // Async on purpose: this runs off the UI path after a share is sent.
    // ignore: avoid_slow_async_io
    if (await file.exists()) await file.delete();
  } catch (error) {
    AppLogger.warning(
      'Could not delete shared file copy',
      tag: 'Share',
      error: error,
    );
  }
}

/// Reads shares delivered by the operating system.
class IncomingShareService {
  /// Creates a service. [plugin] and [shareCacheDirectory] are injectable
  /// for tests.
  IncomingShareService({
    ReceiveSharingIntent? plugin,
    Future<Directory> Function()? shareCacheDirectory,
  })  : _plugin = plugin ?? ReceiveSharingIntent.instance,
        _shareCacheDirectory =
            shareCacheDirectory ?? _platformShareCacheDirectory;

  final ReceiveSharingIntent _plugin;
  final Future<Directory> Function() _shareCacheDirectory;
  final StreamController<void> _unsupported =
      StreamController<void>.broadcast();

  /// Fires when a share contained text or a link, which is not supported.
  Stream<void> get unsupportedShares => _unsupported.stream;

  /// Shares delivered while the app is already running.
  Stream<List<IncomingShare>> get shareStream =>
      _plugin.getMediaStream().map(_supportedItems);

  /// Returns the share that launched the app (if any) and tells the plugin
  /// it has been consumed, so it is not returned again.
  Future<List<IncomingShare>> takeInitialShares() async {
    final media = await _plugin.getInitialMedia();
    await _plugin.reset();
    return _supportedItems(media);
  }

  /// Deletes share copies left in the share cache by an earlier run that
  /// was stopped before the copies were sent or discarded.
  ///
  /// Only top-level files are removed, and only when they look like a copy
  /// the plugin wrote (see [_pluginCopyPattern]) and are older than
  /// [_sweepGracePeriod], so a copy that was just written for a pending
  /// share is never deleted. Files whose name is returned by [pendingPaths]
  /// are kept. The list is read again for each file, so shares that arrive
  /// during the sweep are not deleted. Errors are logged.
  Future<void> sweepStaleCopies(List<String> Function() pendingPaths) async {
    try {
      final directory = await _shareCacheDirectory();
      final now = DateTime.now();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!_pluginCopyPattern.hasMatch(name) &&
            !_pluginThumbnailPattern.hasMatch(name)) {
          continue;
        }
        final inUse = pendingPaths()
            .any((path) => path.split(RegExp(r'[\\/]')).last == name);
        if (inUse) continue;
        try {
          // Async on purpose: this runs off the UI path at app start.
          // ignore: avoid_slow_async_io
          final modified = await entity.lastModified();
          if (now.difference(modified) < _sweepGracePeriod) continue;
        } catch (_) {
          // Without a readable modification time the file is not swept.
          continue;
        }
        await _deleteQuietly(entity.path);
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Could not sweep stale share copies',
        tag: 'Share',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Keeps only photos, videos and files. Text and links are skipped and
  /// reported through [unsupportedShares].
  List<IncomingShare> _supportedItems(List<SharedMediaFile> media) {
    final items = <IncomingShare>[];
    var skippedText = false;
    for (final item in media) {
      if (item.type == SharedMediaType.text ||
          item.type == SharedMediaType.url) {
        skippedText = true;
        continue;
      }
      final mimeType = item.mimeType ??
          lookupMimeType(item.path) ??
          'application/octet-stream';
      items.add(
        IncomingShare(
          path: item.path,
          mimeType: mimeType,
          thumbnailPath: item.thumbnail,
        ),
      );
    }
    if (skippedText) _unsupported.add(null);
    return items;
  }

  /// Android: the app cache directory, where the plugin writes copies.
  /// iOS: the app-group folder, where the share extension writes copies.
  static Future<Directory> _platformShareCacheDirectory() async {
    if (Platform.isIOS) {
      final path =
          await _shareCacheChannel.invokeMethod<String>('shareCacheDirectory');
      if (path == null) {
        throw StateError('App-group share folder is unavailable');
      }
      return Directory(path);
    }
    return getTemporaryDirectory();
  }
}
