import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/utils/logger.dart';

/// Service for displaying local notifications when messages arrive.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// The peer whose chat screen is currently open (suppress notifications for them).
  String? activeChatPeer;

  /// Set by app.dart from didChangeAppLifecycleState.
  ///
  /// While the app is resumed the user is looking at the app, so the in-app
  /// conversation view is the primary surface; a shade notification for the
  /// same event would be a duplicate. Background delivery (the whole point of
  /// the foreground service) sets this to false.
  static bool appResumed = false;

  /// Whether a notification for [fromUser] should be suppressed.
  ///
  /// Single source of truth shared with the incoming-event handler:
  /// - the user currently has that peer's chat open, or
  /// - the app is resumed (the in-app view already surfaces the message).
  static bool isSuppressed(String fromUser) =>
      instance.activeChatPeer == fromUser || appResumed;

  /// Ask Android 13+ for the POST_NOTIFICATIONS runtime permission.
  ///
  /// Resolves true when the permission is granted. On platforms without the
  /// Android plugin this resolves null/true so callers can proceed.
  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return true;
      final granted = await android.requestNotificationsPermission();
      return granted ?? true;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Notification permission request failed',
        tag: 'NotificationService',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Show a notification for an incoming message.
  ///
  /// Suppressed when [fromUser] matches [activeChatPeer] (the user is already
  /// reading that chat) or when the app is resumed ([appResumed]) - in both
  /// cases the in-app conversation view already surfaces the message.
  Future<void> showMessageNotification({
    required String fromUser,
    required String messageBody,
  }) async {
    if (!_initialized) return;
    if (isSuppressed(fromUser)) return;

    const androidDetails = AndroidNotificationDetails(
      'cryptic_messages',
      'Messages',
      channelDescription: 'Incoming encrypted messages',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _plugin.show(
      fromUser.hashCode,
      fromUser,
      messageBody,
      details,
    );
  }
}
