// lib/core/update/update_prompt.dart
//
// The startup update-check dialog (Option A: notify and open).
//
// The auto_upgrade package is headless: it reports whether a newer GitHub
// release exists and where to find it. This app owns the UI and the browser
// hand-off (Option A — notify and open).
//
// The checker is injected by the caller (usually read from
// [releaseCheckerProvider]), and the browser hand-off is delegated to the
// injected [onUpdate] strategy — defined at the call site, not here — which
// keeps this function testable.

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/logger.dart';

/// How much of the release-notes body to show in the dialog before
/// truncating.
const int kMaxReleaseNotesLength = 300;

/// Checks [checker] and shows the update dialog if a newer release exists.
///
/// The check is awaited across an async gap, so the hosting widget may have
/// been disposed by the time it resolves; [context.mounted] is guarded
/// before any dialog is shown. Fire-and-forget safe: this function never
/// throws.
Future<void> maybeShowUpdateDialog(
  BuildContext context, {
  required ReleaseChecker checker,
  required Future<void> Function(UpdateInfo info) onUpdate,
}) async {
  final result = await checker.check();
  if (result is CheckError) {
    AppLogger.debug('Update check failed: ${result.cause}', tag: 'Update');
  }
  if (!context.mounted) return;

  switch (result) {
    case UpdateAvailable(:final info):
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A newer version (${info.latestVersion}) is available.\n'
                'You are running ${info.currentVersion}.\n\n'
                'Open the release page to download it?',
              ),
              if (info.releaseNotes != null &&
                  info.releaseNotes!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _truncate(info.releaseNotes!),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open'),
            ),
          ],
        ),
      );

      if (shouldOpen ?? false) {
        await onUpdate(info);
      }
    case UpToDate():
    case CheckSkipped():
    case CheckError():
      break;
  }
}

/// Opens the release page for [info] in the external browser.
///
/// This is the default [onUpdate] strategy for [maybeShowUpdateDialog].
/// Never throws: a failed launch (no browser available, malformed URL, etc.)
/// is caught and logged.
Future<void> openReleasePage(UpdateInfo info) async {
  try {
    final launched = await launchUrl(
      Uri.parse(info.releasePageUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      AppLogger.warning(
        'Could not open release page: ${info.releasePageUrl}',
        tag: 'Update',
      );
    }
  } catch (e) {
    AppLogger.warning(
      'Could not open release page: $e',
      tag: 'Update',
    );
  }
}

/// Truncates release notes to [kMaxReleaseNotesLength] characters on a word
/// boundary, appending an ellipsis when cut.
String _truncate(String notes) {
  final trimmed = notes.trim();
  if (trimmed.length <= kMaxReleaseNotesLength) return trimmed;
  var cut = trimmed.substring(0, kMaxReleaseNotesLength);
  final lastSpace = cut.lastIndexOf(' ');
  if (lastSpace > 0) {
    cut = cut.substring(0, lastSpace);
  }
  return '${cut.trimRight()}…';
}
