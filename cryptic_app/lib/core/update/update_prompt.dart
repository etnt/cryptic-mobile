// lib/core/update/update_prompt.dart
//
// Self-update prompt for side-loaded builds.
//
// The auto_upgrade package is headless: it reports whether a newer GitHub
// release exists and where to find it. This app owns the UI and the browser
// hand-off (Option A — notify and open).

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/logger.dart';

/// GitHub repository that publishes the release APKs.
const _releaseOwner = 'etnt';
const _releaseRepo = 'cryptic-mobile';

/// Checks GitHub Releases for a newer APK and, if one exists, prompts the user
/// to open the release page in the browser.
///
/// Safe to call unconditionally on startup: the check never throws, is
/// throttled to once per 24h (persisted via [SharedPreferences]), and
/// short-circuits for local `dev` builds (i.e. when `APP_VERSION` is not
/// injected at build time via `--dart-define`).
Future<void> checkAndPromptForUpdate(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();

  final checker = ReleaseChecker(
    owner: _releaseOwner,
    repo: _releaseRepo,
    // Injected at release build time via --dart-define; defaults to the 'dev'
    // sentinel for local builds, which short-circuits the check.
    // ignore: do_not_use_environment
    currentVersion: const String.fromEnvironment(
      'APP_VERSION',
      defaultValue: ReleaseChecker.devVersion,
    ),
    checkStore: SharedPrefsUpdateCheckStore(prefs),
  );

  final result = await checker.check();
  if (result is CheckError) {
    AppLogger.debug('Update check failed: ${result.cause}', tag: 'Update');
    return;
  }
  if (result is! UpdateAvailable) return;

  if (!context.mounted) return;
  final info = result.info;

  final shouldOpen = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update available'),
      content: Text(
        'A newer version (${info.latestVersion}) is available.\n'
        'You are running ${info.currentVersion}.\n\n'
        'Open the release page to download it?',
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
    await launchUrl(
      Uri.parse(info.releasePageUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}
