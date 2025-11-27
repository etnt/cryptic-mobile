// test/core/utils/logger_test.dart
//
// Unit tests for AppLogger
//

import 'package:flutter_test/flutter_test.dart';

import 'package:cryptic_app/core/config/app_config.dart';
import 'package:cryptic_app/core/utils/logger.dart';

void main() {
  group('AppLogger', () {
    setUp(() {
      AppLogger.init(level: LogLevel.debug, enableConsole: false);
    });

    test('should initialize with provided log level', () {
      // AppLogger is initialized, should not throw
      expect(() => AppLogger.info('Test message'), returnsNormally);
    });

    test('should not throw on debug log', () {
      expect(() => AppLogger.debug('Debug message'), returnsNormally);
    });

    test('should not throw on info log', () {
      expect(() => AppLogger.info('Info message'), returnsNormally);
    });

    test('should not throw on warning log', () {
      expect(() => AppLogger.warning('Warning message'), returnsNormally);
    });

    test('should not throw on error log', () {
      expect(() => AppLogger.error('Error message'), returnsNormally);
    });

    test('should handle error objects', () {
      expect(
        () => AppLogger.error(
          'Error with exception',
          error: Exception('Test exception'),
        ),
        returnsNormally,
      );
    });

    test('should handle stack traces', () {
      expect(
        () => AppLogger.error(
          'Error with stack',
          error: Exception('Test'),
          stackTrace: StackTrace.current,
        ),
        returnsNormally,
      );
    });
  });

  group('SecureLogging extension', () {
    test('redacted should mask sensitive patterns', () {
      const input = 'privateKey: abc123def456...';
      expect(input.redacted, contains('[REDACTED]'));
    });

    test('redactAfter should truncate and mask', () {
      const input = 'This is a long secret key value';
      final result = input.redactAfter(10);
      expect(result, equals('This is a ...[REDACTED]'));
    });

    test('redactAfter should return full string if shorter than limit', () {
      const input = 'short';
      final result = input.redactAfter(10);
      expect(result, equals('short'));
    });
  });

  group('AppConfig', () {
    test('development config should have correct defaults', () {
      expect(AppConfig.development.environment, Environment.development);
      expect(AppConfig.development.serverHost, 'localhost');
      expect(AppConfig.development.serverPort, 8443);
      expect(AppConfig.development.useTls, isTrue);
      expect(AppConfig.development.logLevel, LogLevel.debug);
    });

    test('websocketUrl should generate correct URL', () {
      expect(
        AppConfig.development.websocketUrl,
        equals('wss://localhost:8443/ws'),
      );
    });

    test('production config should have less verbose logging', () {
      expect(AppConfig.production.logLevel, LogLevel.warning);
      expect(AppConfig.production.enableConsoleLogging, isFalse);
    });

    test('isDevelopment should return true for development', () {
      expect(AppConfig.development.isDevelopment, isTrue);
      expect(AppConfig.production.isDevelopment, isFalse);
    });

    test('isProduction should return true for production', () {
      expect(AppConfig.production.isProduction, isTrue);
      expect(AppConfig.development.isProduction, isFalse);
    });
  });
}
