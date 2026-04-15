// test/data/storage/preferences/encrypted_preferences_test.dart
//
// Tests for EncryptedPreferences

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:cryptic_app/data/storage/secure_storage/secure_storage_service.dart';
import 'package:cryptic_app/data/storage/preferences/encrypted_preferences.dart';

@GenerateMocks([SecureStorageService])
import 'encrypted_preferences_test.mocks.dart';

void main() {
  late MockSecureStorageService mockStorage;
  late EncryptedPreferences prefs;

  setUp(() {
    mockStorage = MockSecureStorageService();
    prefs = EncryptedPreferences(secureStorage: mockStorage);
  });

  group('EncryptedPreferences', () {
    group('Generic accessors', () {
      test('getBool returns default when key not found', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => null);

        final result = await prefs.getBool('test_key', defaultValue: true);

        expect(result, isTrue);
      });

      test('getBool parses true value', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => 'true');

        final result = await prefs.getBool('test_key');

        expect(result, isTrue);
      });

      test('getBool parses false value', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => 'false');

        final result = await prefs.getBool('test_key');

        expect(result, isFalse);
      });

      test('setBool stores string value', () async {
        when(mockStorage.write(key: 'test_key', value: 'true'))
            .thenAnswer((_) async {});

        await prefs.setBool('test_key', true);

        verify(mockStorage.write(key: 'test_key', value: 'true')).called(1);
      });

      test('getInt returns default when key not found', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => null);

        final result = await prefs.getInt('test_key', defaultValue: 42);

        expect(result, 42);
      });

      test('getInt parses integer value', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => '123');

        final result = await prefs.getInt('test_key');

        expect(result, 123);
      });

      test('setInt stores string value', () async {
        when(mockStorage.write(key: 'test_key', value: '42'))
            .thenAnswer((_) async {});

        await prefs.setInt('test_key', 42);

        verify(mockStorage.write(key: 'test_key', value: '42')).called(1);
      });

      test('getDouble returns default when key not found', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => null);

        final result = await prefs.getDouble('test_key', defaultValue: 1.5);

        expect(result, 1.5);
      });

      test('getDouble parses double value', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => '3.14');

        final result = await prefs.getDouble('test_key');

        expect(result, closeTo(3.14, 0.001));
      });

      test('getString returns null when key not found', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => null);

        final result = await prefs.getString('test_key');

        expect(result, isNull);
      });

      test('getString returns stored value', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => 'hello');

        final result = await prefs.getString('test_key');

        expect(result, 'hello');
      });
    });

    group('Security settings', () {
      test('biometricEnabled defaults to false', () async {
        when(mockStorage.read(key: PreferenceKeys.biometricEnabled))
            .thenAnswer((_) async => null);

        final result = await prefs.biometricEnabled;

        expect(result, isFalse);
      });

      test('setBiometricEnabled stores value', () async {
        when(mockStorage.write(
          key: PreferenceKeys.biometricEnabled,
          value: 'true',
        ),).thenAnswer((_) async {});

        await prefs.setBiometricEnabled(true);

        verify(mockStorage.write(
          key: PreferenceKeys.biometricEnabled,
          value: 'true',
        ),).called(1);
      });

      test('autoLockTimeout defaults to 60', () async {
        when(mockStorage.read(key: PreferenceKeys.autoLockTimeout))
            .thenAnswer((_) async => null);

        final result = await prefs.autoLockTimeout;

        expect(result, 60);
      });

      test('showMessagePreviews defaults to false', () async {
        when(mockStorage.read(key: PreferenceKeys.showMessagePreviews))
            .thenAnswer((_) async => null);

        final result = await prefs.showMessagePreviews;

        expect(result, isFalse);
      });

      test('requireUnlockOnStart defaults to true', () async {
        when(mockStorage.read(key: PreferenceKeys.requireUnlockOnStart))
            .thenAnswer((_) async => null);

        final result = await prefs.requireUnlockOnStart;

        expect(result, isTrue);
      });
    });

    group('Privacy settings', () {
      test('readReceiptsEnabled defaults to false', () async {
        when(mockStorage.read(key: PreferenceKeys.readReceiptsEnabled))
            .thenAnswer((_) async => null);

        final result = await prefs.readReceiptsEnabled;

        expect(result, isFalse);
      });

      test('typingIndicatorsEnabled defaults to false', () async {
        when(mockStorage.read(key: PreferenceKeys.typingIndicatorsEnabled))
            .thenAnswer((_) async => null);

        final result = await prefs.typingIndicatorsEnabled;

        expect(result, isFalse);
      });

      test('lastSeenVisible defaults to false', () async {
        when(mockStorage.read(key: PreferenceKeys.lastSeenVisible))
            .thenAnswer((_) async => null);

        final result = await prefs.lastSeenVisible;

        expect(result, isFalse);
      });

      test('clearClipboardAfterPaste defaults to true', () async {
        when(mockStorage.read(key: PreferenceKeys.clearClipboardAfterPaste))
            .thenAnswer((_) async => null);

        final result = await prefs.clearClipboardAfterPaste;

        expect(result, isTrue);
      });
    });

    group('Appearance settings', () {
      test('themeMode defaults to dark', () async {
        when(mockStorage.read(key: PreferenceKeys.themeMode))
            .thenAnswer((_) async => null);

        final result = await prefs.themeMode;

        expect(result, 'dark');
      });

      test('fontSizeScale defaults to 1.0', () async {
        when(mockStorage.read(key: PreferenceKeys.fontSizeScale))
            .thenAnswer((_) async => null);

        final result = await prefs.fontSizeScale;

        expect(result, 1.0);
      });

      test('highContrastEnabled defaults to false', () async {
        when(mockStorage.read(key: PreferenceKeys.highContrastEnabled))
            .thenAnswer((_) async => null);

        final result = await prefs.highContrastEnabled;

        expect(result, isFalse);
      });
    });

    group('Network settings', () {
      test('connectionTimeout defaults to 30', () async {
        when(mockStorage.read(key: PreferenceKeys.connectionTimeout))
            .thenAnswer((_) async => null);

        final result = await prefs.connectionTimeout;

        expect(result, 30);
      });

      test('autoReconnect defaults to true', () async {
        when(mockStorage.read(key: PreferenceKeys.autoReconnect))
            .thenAnswer((_) async => null);

        final result = await prefs.autoReconnect;

        expect(result, isTrue);
      });

      test('maxReconnectAttempts defaults to 5', () async {
        when(mockStorage.read(key: PreferenceKeys.maxReconnectAttempts))
            .thenAnswer((_) async => null);

        final result = await prefs.maxReconnectAttempts;

        expect(result, 5);
      });
    });

    group('Data management settings', () {
      test('messageRetentionDays defaults to 0', () async {
        when(mockStorage.read(key: PreferenceKeys.messageRetentionDays))
            .thenAnswer((_) async => null);

        final result = await prefs.messageRetentionDays;

        expect(result, 0);
      });

      test('maxMediaCacheMb defaults to 500', () async {
        when(mockStorage.read(key: PreferenceKeys.maxMediaCacheMb))
            .thenAnswer((_) async => null);

        final result = await prefs.maxMediaCacheMb;

        expect(result, 500);
      });

      test('autoDownloadMedia defaults to false', () async {
        when(mockStorage.read(key: PreferenceKeys.autoDownloadMedia))
            .thenAnswer((_) async => null);

        final result = await prefs.autoDownloadMedia;

        expect(result, isFalse);
      });
    });

    group('App state', () {
      test('recordAppOpened stores current timestamp', () async {
        when(mockStorage.write(
          key: anyNamed('key'),
          value: anyNamed('value'),
        ),).thenAnswer((_) async {});

        await prefs.recordAppOpened();

        verify(mockStorage.write(
          key: PreferenceKeys.lastOpenedAt,
          value: anyNamed('value'),
        ),).called(1);
      });

      test('lastOpenedAt returns null when never opened', () async {
        when(mockStorage.read(key: PreferenceKeys.lastOpenedAt))
            .thenAnswer((_) async => null);

        final result = await prefs.lastOpenedAt;

        expect(result, isNull);
      });

      test('onboardingCompleted defaults to false', () async {
        when(mockStorage.read(key: PreferenceKeys.onboardingCompleted))
            .thenAnswer((_) async => null);

        final result = await prefs.onboardingCompleted;

        expect(result, isFalse);
      });
    });

    group('Bulk operations', () {
      test('resetToDefaults removes all preference keys', () async {
        when(mockStorage.readAll()).thenAnswer((_) async => {
              'cryptic_pref_key1': 'value1',
              'cryptic_pref_key2': 'value2',
              'cryptic_other_key': 'value3',
            },);
        when(mockStorage.delete(key: anyNamed('key')))
            .thenAnswer((_) async {});

        await prefs.resetToDefaults();

        verify(mockStorage.delete(key: 'cryptic_pref_key1')).called(1);
        verify(mockStorage.delete(key: 'cryptic_pref_key2')).called(1);
        verifyNever(mockStorage.delete(key: 'cryptic_other_key'));
      });
    });
  });
}
