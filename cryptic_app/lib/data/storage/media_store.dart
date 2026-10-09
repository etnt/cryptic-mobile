/// App-private storage for decrypted attachment media.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'preferences/encrypted_preferences.dart';

class MediaStore {
  MediaStore({Future<Directory> Function()? documentsDirectoryProvider})
      : _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationSupportDirectory;

  static const _securityChannel = MethodChannel('cryptic/media_storage');
  static const _recentMediaAge = Duration(days: 30);

  final Future<Directory> Function() _documentsDirectoryProvider;

  Future<String> resolvePath(
    String peer,
    String fileId, {
    String? fileName,
  }) async {
    final root = await _mediaDirectory();
    final extension = fileName == null ? '' : _safeExtension(fileName);
    return '${root.path}/${_safeSegment(peer)}/${_safeSegment(fileId)}$extension';
  }

  Future<String> save({
    required String peer,
    required String fileId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final root = await _mediaDirectory();
    final peerDir = Directory('${root.path}/${_safeSegment(peer)}');
    await peerDir.create(recursive: true);
    await _secureDirectory(peerDir);
    final extension = _safeExtension(fileName);
    final file = File('${peerDir.path}/${_safeSegment(fileId)}$extension');
    // Keep exclusive-create errors outside cleanup: if the path already exists,
    // it belongs to an earlier save and must not be removed.
    await file.create(exclusive: true);
    try {
      // Secure the empty file before writing any attachment bytes.
      await _secureFile(file);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Async on purpose: large attachments must not block the UI isolate.
      // ignore: avoid_slow_async_io
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return file.path;
  }

  /// Evict old unreferenced media and return the paths that were removed.
  ///
  /// Media referenced by current or recent messages must be passed in
  /// [protectedPaths]. Media younger than 30 days is also kept as a safeguard.
  Future<List<String>> evict({
    int? maxMediaCacheMb,
    Set<String> protectedPaths = const {},
  }) async {
    var maximum = maxMediaCacheMb;
    if (maximum == null) {
      try {
        maximum = await EncryptedPreferences().maxMediaCacheMb;
      } catch (_) {
        maximum = 500;
      }
    }
    final root = await _mediaDirectory();
    // Async on purpose: large attachments must not block the UI isolate.
    // ignore: avoid_slow_async_io
    if (!await root.exists()) return const [];
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    final stats = <(File, FileStat)>[];
    var totalBytes = 0;
    for (final file in files) {
      // Async on purpose: large attachments must not block the UI isolate.
      // ignore: avoid_slow_async_io
      final stat = await file.stat();
      totalBytes += stat.size;
      stats.add((file, stat));
    }
    final limit = maximum * 1024 * 1024;
    stats.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    final removed = <String>[];
    // Received media older than 30 days may be evicted when the cache limit is
    // exceeded, unless a recent message still references the file.
    final recentCutoff = DateTime.now().subtract(_recentMediaAge);
    for (final entry in stats) {
      if (totalBytes <= limit) break;
      final path = entry.$1.path;
      if (protectedPaths.contains(path) ||
          entry.$2.modified.isAfter(recentCutoff)) {
        continue;
      }
      await entry.$1.delete();
      removed.add(path);
      totalBytes -= entry.$2.size;
    }
    return removed;
  }

  Future<Directory> _mediaDirectory() async {
    final support = await _documentsDirectoryProvider();
    final directory = Directory('${support.path}/media');
    await directory.create(recursive: true);
    await _secureDirectory(directory);
    return directory;
  }

  Future<void> _secureDirectory(Directory directory) async {
    try {
      await _securityChannel.invokeMethod<void>(
        'securePath',
        {'path': directory.path},
      );
    } on MissingPluginException catch (error) {
      debugPrint('Media directory protection plugin is unavailable: $error');
      if (Platform.isIOS) rethrow;
      // Android backup rules and non-mobile platforms need no channel handler.
    }
  }

  Future<void> _secureFile(File file) async {
    try {
      await _securityChannel.invokeMethod<void>(
        'securePath',
        {'path': file.path},
      );
    } on MissingPluginException catch (error) {
      debugPrint('Media file protection plugin is unavailable: $error');
      if (Platform.isIOS) rethrow;
      // Android backup rules and non-mobile platforms need no channel handler.
    }
  }

  static String _safeSegment(String value) {
    final safe = value.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    final segment = safe.isEmpty ? 'attachment' : safe;
    final hash = _stableHash(value).toRadixString(16).padLeft(8, '0');
    return '${segment}_$hash';
  }

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static String _safeExtension(String name) {
    final basename = name.replaceAll(r'\', '/').split('/').last;
    final dot = basename.lastIndexOf('.');
    if (dot < 0 || dot == basename.length - 1) return '';
    final extension = basename.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension) ? extension : '';
  }
}
