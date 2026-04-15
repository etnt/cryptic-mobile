// lib/data/storage/preferences/encrypted_preferences.dart
//
// Encrypted Preferences - Secure storage for app settings
//

import '../secure_storage/secure_storage_service.dart';

/// Keys for encrypted preferences.
abstract class PreferenceKeys {
  /// Prefix for preference entries.
  static const prefix = 'cryptic_pref_';

  // ─────────────────────────────────────────────────────────────────────────
  // Security Settings
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether biometric authentication is enabled.
  static const biometricEnabled = '${prefix}biometric_enabled';

  /// Auto-lock timeout in seconds (0 = disabled).
  static const autoLockTimeout = '${prefix}auto_lock_timeout';

  /// Whether to show message previews in notifications.
  static const showMessagePreviews = '${prefix}show_message_previews';

  /// Whether to require unlock on app start.
  static const requireUnlockOnStart = '${prefix}require_unlock_on_start';

  // ─────────────────────────────────────────────────────────────────────────
  // Privacy Settings
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether read receipts are enabled.
  static const readReceiptsEnabled = '${prefix}read_receipts_enabled';

  /// Whether typing indicators are enabled.
  static const typingIndicatorsEnabled = '${prefix}typing_indicators_enabled';

  /// Whether last seen is visible.
  static const lastSeenVisible = '${prefix}last_seen_visible';

  /// Whether to clear clipboard after paste.
  static const clearClipboardAfterPaste = '${prefix}clear_clipboard';

  // ─────────────────────────────────────────────────────────────────────────
  // Appearance Settings
  // ─────────────────────────────────────────────────────────────────────────

  /// Theme mode: 'light', 'dark', 'system'.
  static const themeMode = '${prefix}theme_mode';

  /// Font size scale (1.0 = default).
  static const fontSizeScale = '${prefix}font_size_scale';

  /// Whether to use high contrast colors.
  static const highContrastEnabled = '${prefix}high_contrast';

  // ─────────────────────────────────────────────────────────────────────────
  // Network Settings
  // ─────────────────────────────────────────────────────────────────────────

  /// Connection timeout in seconds.
  static const connectionTimeout = '${prefix}connection_timeout';

  /// Whether to auto-reconnect on connection loss.
  static const autoReconnect = '${prefix}auto_reconnect';

  /// Maximum reconnect attempts.
  static const maxReconnectAttempts = '${prefix}max_reconnect_attempts';

  // ─────────────────────────────────────────────────────────────────────────
  // Data Management
  // ─────────────────────────────────────────────────────────────────────────

  /// Days to keep messages before auto-delete (0 = never).
  static const messageRetentionDays = '${prefix}message_retention_days';

  /// Maximum media cache size in MB.
  static const maxMediaCacheMb = '${prefix}max_media_cache_mb';

  /// Whether to download media automatically.
  static const autoDownloadMedia = '${prefix}auto_download_media';

  // ─────────────────────────────────────────────────────────────────────────
  // App State
  // ─────────────────────────────────────────────────────────────────────────

  /// When the app was last opened.
  static const lastOpenedAt = '${prefix}last_opened_at';

  /// Whether onboarding has been completed.
  static const onboardingCompleted = '${prefix}onboarding_completed';

  /// App version for migration tracking.
  static const lastAppVersion = '${prefix}last_app_version';
}

/// Secure encrypted preferences storage.
///
/// Provides type-safe access to app settings stored in secure storage.
/// All preferences are encrypted at rest.
class EncryptedPreferences {
  /// Creates encrypted preferences.
  EncryptedPreferences({
    SecureStorageService? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageService();

  final SecureStorageService _secureStorage;

  // ─────────────────────────────────────────────────────────────────────────
  // Generic Accessors
  // ─────────────────────────────────────────────────────────────────────────

  /// Gets a boolean preference.
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final value = await _secureStorage.read(key: key);
    if (value == null) return defaultValue;
    return value == 'true';
  }

  /// Sets a boolean preference.
  Future<void> setBool(String key, bool value) async {
    await _secureStorage.write(key: key, value: value.toString());
  }

  /// Gets an integer preference.
  Future<int> getInt(String key, {int defaultValue = 0}) async {
    final value = await _secureStorage.read(key: key);
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  /// Sets an integer preference.
  Future<void> setInt(String key, int value) async {
    await _secureStorage.write(key: key, value: value.toString());
  }

  /// Gets a double preference.
  Future<double> getDouble(String key, {double defaultValue = 0.0}) async {
    final value = await _secureStorage.read(key: key);
    if (value == null) return defaultValue;
    return double.tryParse(value) ?? defaultValue;
  }

  /// Sets a double preference.
  Future<void> setDouble(String key, double value) async {
    await _secureStorage.write(key: key, value: value.toString());
  }

  /// Gets a string preference.
  Future<String?> getString(String key) async => await _secureStorage.read(key: key);

  /// Sets a string preference.
  Future<void> setString(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  /// Removes a preference.
  Future<void> remove(String key) async {
    await _secureStorage.delete(key: key);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Security Settings
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether biometric authentication is enabled.
  Future<bool> get biometricEnabled =>
      getBool(PreferenceKeys.biometricEnabled);

  /// Sets biometric authentication enabled.
  Future<void> setBiometricEnabled(bool value) =>
      setBool(PreferenceKeys.biometricEnabled, value);

  /// Auto-lock timeout in seconds.
  Future<int> get autoLockTimeout =>
      getInt(PreferenceKeys.autoLockTimeout, defaultValue: 60);

  /// Sets auto-lock timeout.
  Future<void> setAutoLockTimeout(int seconds) =>
      setInt(PreferenceKeys.autoLockTimeout, seconds);

  /// Whether to show message previews in notifications.
  Future<bool> get showMessagePreviews =>
      getBool(PreferenceKeys.showMessagePreviews);

  /// Sets show message previews.
  Future<void> setShowMessagePreviews(bool value) =>
      setBool(PreferenceKeys.showMessagePreviews, value);

  /// Whether to require unlock on app start.
  Future<bool> get requireUnlockOnStart =>
      getBool(PreferenceKeys.requireUnlockOnStart, defaultValue: true);

  /// Sets require unlock on start.
  Future<void> setRequireUnlockOnStart(bool value) =>
      setBool(PreferenceKeys.requireUnlockOnStart, value);

  // ─────────────────────────────────────────────────────────────────────────
  // Privacy Settings
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether read receipts are enabled.
  Future<bool> get readReceiptsEnabled =>
      getBool(PreferenceKeys.readReceiptsEnabled);

  /// Sets read receipts enabled.
  Future<void> setReadReceiptsEnabled(bool value) =>
      setBool(PreferenceKeys.readReceiptsEnabled, value);

  /// Whether typing indicators are enabled.
  Future<bool> get typingIndicatorsEnabled =>
      getBool(PreferenceKeys.typingIndicatorsEnabled);

  /// Sets typing indicators enabled.
  Future<void> setTypingIndicatorsEnabled(bool value) =>
      setBool(PreferenceKeys.typingIndicatorsEnabled, value);

  /// Whether last seen is visible.
  Future<bool> get lastSeenVisible =>
      getBool(PreferenceKeys.lastSeenVisible);

  /// Sets last seen visible.
  Future<void> setLastSeenVisible(bool value) =>
      setBool(PreferenceKeys.lastSeenVisible, value);

  /// Whether to clear clipboard after paste.
  Future<bool> get clearClipboardAfterPaste =>
      getBool(PreferenceKeys.clearClipboardAfterPaste, defaultValue: true);

  /// Sets clear clipboard after paste.
  Future<void> setClearClipboardAfterPaste(bool value) =>
      setBool(PreferenceKeys.clearClipboardAfterPaste, value);

  // ─────────────────────────────────────────────────────────────────────────
  // Appearance Settings
  // ─────────────────────────────────────────────────────────────────────────

  /// Theme mode.
  Future<String> get themeMode async =>
      await getString(PreferenceKeys.themeMode) ?? 'dark';

  /// Sets theme mode.
  Future<void> setThemeMode(String mode) =>
      setString(PreferenceKeys.themeMode, mode);

  /// Font size scale.
  Future<double> get fontSizeScale =>
      getDouble(PreferenceKeys.fontSizeScale, defaultValue: 1);

  /// Sets font size scale.
  Future<void> setFontSizeScale(double scale) =>
      setDouble(PreferenceKeys.fontSizeScale, scale);

  /// Whether high contrast is enabled.
  Future<bool> get highContrastEnabled =>
      getBool(PreferenceKeys.highContrastEnabled);

  /// Sets high contrast enabled.
  Future<void> setHighContrastEnabled(bool value) =>
      setBool(PreferenceKeys.highContrastEnabled, value);

  // ─────────────────────────────────────────────────────────────────────────
  // Network Settings
  // ─────────────────────────────────────────────────────────────────────────

  /// Connection timeout in seconds.
  Future<int> get connectionTimeout =>
      getInt(PreferenceKeys.connectionTimeout, defaultValue: 30);

  /// Sets connection timeout.
  Future<void> setConnectionTimeout(int seconds) =>
      setInt(PreferenceKeys.connectionTimeout, seconds);

  /// Whether auto-reconnect is enabled.
  Future<bool> get autoReconnect =>
      getBool(PreferenceKeys.autoReconnect, defaultValue: true);

  /// Sets auto-reconnect.
  Future<void> setAutoReconnect(bool value) =>
      setBool(PreferenceKeys.autoReconnect, value);

  /// Maximum reconnect attempts.
  Future<int> get maxReconnectAttempts =>
      getInt(PreferenceKeys.maxReconnectAttempts, defaultValue: 5);

  /// Sets max reconnect attempts.
  Future<void> setMaxReconnectAttempts(int attempts) =>
      setInt(PreferenceKeys.maxReconnectAttempts, attempts);

  // ─────────────────────────────────────────────────────────────────────────
  // Data Management
  // ─────────────────────────────────────────────────────────────────────────

  /// Message retention in days (0 = forever).
  Future<int> get messageRetentionDays =>
      getInt(PreferenceKeys.messageRetentionDays);

  /// Sets message retention days.
  Future<void> setMessageRetentionDays(int days) =>
      setInt(PreferenceKeys.messageRetentionDays, days);

  /// Maximum media cache size in MB.
  Future<int> get maxMediaCacheMb =>
      getInt(PreferenceKeys.maxMediaCacheMb, defaultValue: 500);

  /// Sets max media cache size.
  Future<void> setMaxMediaCacheMb(int mb) =>
      setInt(PreferenceKeys.maxMediaCacheMb, mb);

  /// Whether to auto-download media.
  Future<bool> get autoDownloadMedia =>
      getBool(PreferenceKeys.autoDownloadMedia);

  /// Sets auto-download media.
  Future<void> setAutoDownloadMedia(bool value) =>
      setBool(PreferenceKeys.autoDownloadMedia, value);

  // ─────────────────────────────────────────────────────────────────────────
  // App State
  // ─────────────────────────────────────────────────────────────────────────

  /// Records when the app was last opened.
  Future<void> recordAppOpened() async {
    await setInt(
      PreferenceKeys.lastOpenedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Gets when the app was last opened.
  Future<DateTime?> get lastOpenedAt async {
    final ms = await getInt(PreferenceKeys.lastOpenedAt);
    if (ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Whether onboarding has been completed.
  Future<bool> get onboardingCompleted =>
      getBool(PreferenceKeys.onboardingCompleted);

  /// Marks onboarding as completed.
  Future<void> setOnboardingCompleted(bool value) =>
      setBool(PreferenceKeys.onboardingCompleted, value);

  /// Gets the last recorded app version.
  Future<String?> get lastAppVersion =>
      getString(PreferenceKeys.lastAppVersion);

  /// Sets the app version.
  Future<void> setLastAppVersion(String version) =>
      setString(PreferenceKeys.lastAppVersion, version);

  // ─────────────────────────────────────────────────────────────────────────
  // Bulk Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Resets all preferences to defaults.
  Future<void> resetToDefaults() async {
    final allKeys = await _secureStorage.readAll();
    for (final key in allKeys.keys) {
      if (key.startsWith(PreferenceKeys.prefix)) {
        await _secureStorage.delete(key: key);
      }
    }
  }

  /// Gets all preferences as a map (for debugging).
  Future<Map<String, dynamic>> getAllPreferences() async => {
      'biometric_enabled': await biometricEnabled,
      'auto_lock_timeout': await autoLockTimeout,
      'show_message_previews': await showMessagePreviews,
      'require_unlock_on_start': await requireUnlockOnStart,
      'read_receipts_enabled': await readReceiptsEnabled,
      'typing_indicators_enabled': await typingIndicatorsEnabled,
      'last_seen_visible': await lastSeenVisible,
      'clear_clipboard_after_paste': await clearClipboardAfterPaste,
      'theme_mode': await themeMode,
      'font_size_scale': await fontSizeScale,
      'high_contrast_enabled': await highContrastEnabled,
      'connection_timeout': await connectionTimeout,
      'auto_reconnect': await autoReconnect,
      'max_reconnect_attempts': await maxReconnectAttempts,
      'message_retention_days': await messageRetentionDays,
      'max_media_cache_mb': await maxMediaCacheMb,
      'auto_download_media': await autoDownloadMedia,
      'onboarding_completed': await onboardingCompleted,
      'last_app_version': await lastAppVersion,
    };
}
