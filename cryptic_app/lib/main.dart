// lib/main.dart
//
// Cryptic Mobile - Entry point
// End-to-end encrypted messaging client
//

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/utils/logger.dart';
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

  runApp(
    // ProviderScope enables Riverpod throughout the app
    const ProviderScope(
      child: CrypticApp(),
    ),
  );
}
