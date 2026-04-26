import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  /// Suppressed if [fromUser] matches [activeChatPeer].
  Future<void> showMessageNotification({
    required String fromUser,
    required String messageBody,
  }) async {
    if (!_initialized) return;
    if (fromUser == activeChatPeer) return;

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
