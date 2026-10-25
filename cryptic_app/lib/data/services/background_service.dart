// lib/data/services/background_service.dart
//
// Foreground-service wrapper for the Android background message connection.
//
// Design (see docs/INCOMING-MESSAGE-NOTIFICATION-PLAN.md):
// - The service is a KEEP-ALIVE only. It hosts a no-op TaskHandler and exists
//   to stop Android from suspending the UI isolate, where the CrypticEngine
//   and its WebSocket connection live.
// - There is NO second engine, no second database handle, and no stored
//   passphrase. All crypto and persistence stay in the UI isolate.
// - iOS is not supported: every call is guarded with Platform.isAndroid.

import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/utils/logger.dart';

/// Singleton wrapper around flutter_foreground_task.
class BackgroundService {
  static final BackgroundService _instance = BackgroundService._();
  static BackgroundService get instance => _instance;

  BackgroundService._();

  bool _initialized = false;

  /// Set when the OS destroyed the service because the dataSync runtime cap
  /// (about 6 h/day on Android 15) was hit. Read by app.dart so the next
  /// resume can restart the service.
  bool _timedOut = false;

  /// Whether the OS killed the last service run because of a dataSync timeout.
  bool get timedOut => _timedOut;

  /// Marks the service as killed by the OS dataSync runtime cap.
  void markTimedOut() => _timedOut = true;

  /// Android notification channel for the permanent status notification.
  static const String channelId = 'cryptic_connection';

  /// Whether the platform can host the background connection at all.
  bool get isSupported => Platform.isAndroid;

  /// Initialize the plugin (notification channel options + task options).
  ///
  /// Safe to call multiple times; only the first call takes effect.
  void init() {
    if (!isSupported || _initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: channelId,
        channelName: 'Background connection',
        channelDescription: 'Keeps the encrypted message connection alive',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showBadge: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      // No periodic task handler work is needed: the connection lives in the
      // UI isolate. Wake lock is not held continuously - the foreground
      // service itself already prevents process death.
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
    AppLogger.info('BackgroundService initialized', tag: 'BackgroundService');
  }

  /// Start the foreground service. No-op on unsupported platforms or if it
  /// is already running.
  Future<void> start() async {
    if (!isSupported) return;
    init();
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'Cryptic',
        notificationText: 'Background connection enabled',
        callback: startCallback,
      );
      AppLogger.info(
        'BackgroundService start: ${result.runtimeType}',
        tag: 'BackgroundService',
      );
      // A fresh start clears any earlier dataSync-timeout flag.
      _timedOut = false;
    } catch (error, stackTrace) {
      // Starting the service can fail if POST_NOTIFICATIONS is denied or the
      // OS blocks dataSync startup. The app keeps working foreground-only.
      AppLogger.warning(
        'BackgroundService failed to start',
        tag: 'BackgroundService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stop the foreground service. No-op on unsupported platforms.
  Future<void> stop() async {
    if (!isSupported) return;
    try {
      if (!(await FlutterForegroundTask.isRunningService)) return;
      await FlutterForegroundTask.stopService();
      AppLogger.info('BackgroundService stopped', tag: 'BackgroundService');
    } catch (error, stackTrace) {
      AppLogger.warning(
        'BackgroundService failed to stop',
        tag: 'BackgroundService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Whether the foreground service is currently running.
  Future<bool> get isRunning async {
    if (!isSupported) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  /// Whether the app is exempt from battery optimization (Doze whitelist).
  Future<bool> get isBatteryExempt async {
    if (!isSupported) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  /// Open the system dialog asking the user to ignore battery optimizations.
  Future<bool> requestBatteryExemption() async {
    if (!isSupported) return false;
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Battery exemption request failed',
        tag: 'BackgroundService',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Open the battery-optimization settings page for this app.
  Future<bool> openBatterySettings() async {
    if (!isSupported) return false;
    try {
      return await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (_) {
      return false;
    }
  }
}

/// Top-level entry point invoked by the plugin when the service starts.
///
/// The connection intentionally stays in the UI isolate; this handler is a
/// no-op whose only job is to keep the service attached to a valid handler.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

/// No-op TaskHandler: the foreground service is a keep-alive only.
class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (!isTimeout) return;
    // Android 15 caps dataSync runtime at ~6 h/day: the OS destroys the
    // service and nothing else restarts it. Flag the singleton so app.dart
    // can restart it on the next resume (the handler runs in the UI isolate).
    AppLogger.warning(
      'BackgroundService destroyed by the OS dataSync runtime cap; '
      'service will restart on next app resume',
      tag: 'BackgroundService',
    );
    BackgroundService.instance.markTimedOut();
  }
}
