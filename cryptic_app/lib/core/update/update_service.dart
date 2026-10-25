// lib/core/update/update_service.dart
//
// Riverpod wiring for the GitHub Releases update check (Option A).
//
// [releaseCheckerProvider] has a default checker with no throttle store, so
// every launch would hit GitHub if it were not overridden. `main()` overrides
// it with a prefs-backed store (the 24h throttle); tests override it with a
// checker returning a canned result. In `dev` builds (`appVersion == 'dev'`,
// i.e. `APP_VERSION` not injected via `--dart-define`) the check
// short-circuits to [CheckSkipped] without any network access.

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub account or organization that owns [releaseRepo].
const releaseOwner = 'etnt';

/// Name of the GitHub repository (under [releaseOwner]) that publishes the
/// release APKs.
const releaseRepo = 'cryptic-mobile';

/// App version injected at release build time via `--dart-define`.
///
/// Defaults to the `'dev'` sentinel for local builds, which short-circuits
/// the update check.
// ignore: do_not_use_environment
const _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: ReleaseChecker.devVersion,
);

/// Supplies the release checker. Override in `main()` with a prefs-backed
/// store; tests override with a checker returning a fake result.
final releaseCheckerProvider =
    Provider<ReleaseChecker>((ref) => buildReleaseChecker(null));

/// Builds the release checker for this app.
///
/// The default provider passes a `null` [prefs] (no throttle store, so every
/// launch would check once); `main()` passes real preferences so the check is
/// throttled to once per 24h.
ReleaseChecker buildReleaseChecker(SharedPreferences? prefs) =>
    ReleaseChecker(
      owner: releaseOwner,
      repo: releaseRepo,
      currentVersion: _appVersion,
      checkStore: prefs == null ? null : SharedPrefsUpdateCheckStore(prefs),
    );
