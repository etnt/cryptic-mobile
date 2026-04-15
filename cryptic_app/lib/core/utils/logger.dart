// lib/core/utils/logger.dart
//
// Application logging utility with security-aware formatting
//

import 'dart:developer' as developer;

import '../config/app_config.dart';

/// Centralized logging utility for Cryptic.
///
/// Provides structured logging with:
/// - Log level filtering
/// - Secret redaction to prevent key leakage
/// - Consistent formatting across the app
/// - Optional console output
abstract class AppLogger {
  static LogLevel _level = LogLevel.debug;
  static bool _enableConsole = true;

  // Patterns that should be redacted from logs
  static final List<RegExp> _sensitivePatterns = [
    // Base64 encoded keys (32+ chars of base64)
    RegExp('[A-Za-z0-9+/]{32,}={0,2}'),
    // Hex encoded keys (64+ hex chars)
    RegExp('[0-9a-fA-F]{64,}'),
    // Passphrases in common formats
    RegExp(r'passphrase["\s:=]+.+', caseSensitive: false),
    RegExp(r'password["\s:=]+.+', caseSensitive: false),
    // Private key markers
    RegExp(r'private.?key["\s:=]+.+', caseSensitive: false),
    // Secret key markers
    RegExp(r'secret.?key["\s:=]+.+', caseSensitive: false),
  ];

  /// Initialize the logger with configuration.
  static void init({
    LogLevel level = LogLevel.debug,
    bool enableConsole = true,
  }) {
    _level = level;
    _enableConsole = enableConsole;
  }

  /// Log a debug message.
  ///
  /// Use for detailed diagnostic information during development.
  static void debug(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.debug, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Log an informational message.
  ///
  /// Use for general operational messages.
  static void info(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.info, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Log a warning message.
  ///
  /// Use for potentially problematic situations.
  static void warning(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.warning, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Log an error message.
  ///
  /// Use for error conditions that should be investigated.
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Log a message at the specified level.
  static void _log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Filter by log level
    if (level.index < _level.index) return;

    // Redact sensitive information
    final safeMessage = _redactSensitive(message);
    final safeError = error != null ? _redactSensitive(error.toString()) : null;

    // Format the message
    final timestamp = DateTime.now().toIso8601String();
    final levelName = level.name.toUpperCase().padRight(5);
    final tagPrefix = tag != null ? '[$tag] ' : '';
    final formatted = '$timestamp $levelName $tagPrefix$safeMessage';

    // Output to console/debug
    if (_enableConsole) {
      developer.log(
        formatted,
        name: 'Cryptic',
        error: safeError,
        stackTrace: stackTrace,
        level: _levelToInt(level),
      );
    }

    // TODO(M8): Add crash reporting integration for production errors
  }

  /// Redact sensitive information from a string.
  ///
  /// Replaces patterns that might contain keys or secrets with [REDACTED].
  static String _redactSensitive(String input) {
    var result = input;
    for (final pattern in _sensitivePatterns) {
      result = result.replaceAll(pattern, '[REDACTED]');
    }
    return result;
  }

  /// Convert log level to integer for developer.log.
  static int _levelToInt(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500; // FINE
      case LogLevel.info:
        return 800; // INFO
      case LogLevel.warning:
        return 900; // WARNING
      case LogLevel.error:
        return 1000; // SEVERE
      case LogLevel.none:
        return 2000;
    }
  }
}

/// Extension for logging sensitive data safely.
extension SecureLogging on String {
  /// Returns a redacted version suitable for logging.
  String get redacted => AppLogger._redactSensitive(this);

  /// Returns first N characters with rest redacted.
  String redactAfter(int chars) {
    if (length <= chars) return this;
    return '${substring(0, chars)}...[REDACTED]';
  }
}
