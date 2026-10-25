// lib/main.dart
//
// Cryptic Mobile - Entry point
// End-to-end encrypted messaging client
//

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/update/update_service.dart';
import 'core/utils/logger.dart';
import 'data/services/background_service.dart';
import 'data/services/notification_service.dart';
import 'presentation/app.dart';

/// Application entry point.
///
/// Initializes core services and starts the Flutter application
/// with Riverpod for state management.
Future<void> main() async {
  // Ensure Flutter bindings are initialized before any async operations
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging first for debugging during startup
  AppLogger.init(
    level: AppConfig.current.logLevel,
    enableConsole: AppConfig.current.enableConsoleLogging,
  );

  AppLogger.info('Starting Cryptic Mobile...');
  AppLogger.info('Environment: ${AppConfig.current.environment.name}');

  // TODO(M2): Initialize secure storage
  // TODO(M3): Initialize database
  // TODO(M5): Load cached sessions

  // Preferences for the update-check throttle. A failure must not block
  // startup: fall back to a checker without a store (throttle disabled).
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (error, stackTrace) {
    AppLogger.warning(
      'SharedPreferences unavailable; update-check throttle disabled',
      tag: 'App',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // Initialize local notifications
  await NotificationService.instance.initialize();

  // Initialize the Android foreground-service wrapper (keep-alive for the
  // background message connection). The engine itself stays in this isolate.
  BackgroundService.instance.init();
  // Required by flutter_foreground_task v11 for TaskHandler<->UI port setup.
  FlutterForegroundTask.initCommunicationPort();

  runApp(
    // ProviderScope enables Riverpod throughout the app. The update checker
    // is overridden with a prefs-backed store so the check is throttled to
    // once per 24h.
    ProviderScope(
      overrides: [
        releaseCheckerProvider.overrideWithValue(buildReleaseChecker(prefs)),
      ],
      child: const CrypticApp(),
    ),
  );
}
