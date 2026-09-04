// test/data/storage/secure_storage/secure_storage_service_test.dart
//
// Tests for SecureStorageService

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:cryptic_app/data/storage/secure_storage/secure_storage_service.dart';

@GenerateMocks([FlutterSecureStorage])
import 'secure_storage_service_test.mocks.dart';

void main() {
  late MockFlutterSecureStorage mockStorage;
  late SecureStorageService service;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    service = SecureStorageService(storage: mockStorage);
  });

  group('SecureStorageService', () {
    group('String operations', () {
      test('write stores string value', () async {
        when(mockStorage.write(key: 'test_key', value: 'test_value'))
            .thenAnswer((_) async {});

        await service.write(key: 'test_key', value: 'test_value');

        verify(mockStorage.write(key: 'test_key', value: 'test_value'))
            .called(1);
      });

      test('read returns stored string value', () async {
        when(mockStorage.read(key: 'test_key'))
            .thenAnswer((_) async => 'test_value');

        final result = await service.read(key: 'test_key');

        expect(result, 'test_value');
      });

      test('read returns null for missing key', () async {
        when(mockStorage.read(key: 'missing_key'))
            .thenAnswer((_) async => null);

        final result = await service.read(key: 'missing_key');

        expect(result, isNull);
      });

      test('delete removes key', () async {
        when(mockStorage.delete(key: 'test_key')).thenAnswer((_) async {});

        await service.delete(key: 'test_key');

        verify(mockStorage.delete(key: 'test_key')).called(1);
      });

      test('containsKey returns true for existing key', () async {
        when(mockStorage.containsKey(key: 'test_key'))
            .thenAnswer((_) async => true);

        final result = await service.containsKey(key: 'test_key');

        expect(result, isTrue);
      });

      test('containsKey returns false for missing key', () async {
        when(mockStorage.containsKey(key: 'missing_key'))
            .thenAnswer((_) async => false);

        final result = await service.containsKey(key: 'missing_key');

        expect(result, isFalse);
      });

      test('readAll returns all stored values', () async {
        when(mockStorage.readAll()).thenAnswer(
          (_) async => {
            'key1': 'value1',
            'key2': 'value2',
          },
        );

        final result = await service.readAll();

        expect(result, {'key1': 'value1', 'key2': 'value2'});
      });

      test('deleteAll clears all values', () async {
        when(mockStorage.deleteAll()).thenAnswer((_) async {});

        await service.deleteAll();

        verify(mockStorage.deleteAll()).called(1);
      });
    });

    group('Binary operations', () {
      test('writeBytes encodes to base64', () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final expected = base64Encode(bytes);

        when(mockStorage.write(key: 'binary_key', value: expected))
            .thenAnswer((_) async {});

        await service.writeBytes(key: 'binary_key', value: bytes);

        verify(mockStorage.write(key: 'binary_key', value: expected)).called(1);
      });

      test('readBytes decodes from base64', () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final encoded = base64Encode(bytes);

        when(mockStorage.read(key: 'binary_key'))
            .thenAnswer((_) async => encoded);

        final result = await service.readBytes(key: 'binary_key');

        expect(result, equals(bytes));
      });

      test('readBytes returns null for missing key', () async {
        when(mockStorage.read(key: 'missing_key'))
            .thenAnswer((_) async => null);

        final result = await service.readBytes(key: 'missing_key');

        expect(result, isNull);
      });
    });

    group('JSON operations', () {
      test('writeJson encodes to JSON string', () async {
        final data = {'name': 'test', 'value': 42};
        final expected = jsonEncode(data);

        when(mockStorage.write(key: 'json_key', value: expected))
            .thenAnswer((_) async {});

        await service.writeJson(key: 'json_key', value: data);

        verify(mockStorage.write(key: 'json_key', value: expected)).called(1);
      });

      test('readJson decodes from JSON string', () async {
        final data = {'name': 'test', 'value': 42};
        final encoded = jsonEncode(data);

        when(mockStorage.read(key: 'json_key'))
            .thenAnswer((_) async => encoded);

        final result = await service.readJson(key: 'json_key');

        expect(result, equals(data));
      });

      test('readJson returns null for missing key', () async {
        when(mockStorage.read(key: 'missing_key'))
            .thenAnswer((_) async => null);

        final result = await service.readJson(key: 'missing_key');

        expect(result, isNull);
      });
    });
  });
}
