import 'dart:typed_data';

import 'package:cryptic_app/data/network/websocket/mtls_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MtlsConfig', () {
    late MtlsConfig config;

    setUp(() {
      config = MtlsConfig(
        clientCertificate: Uint8List.fromList([1, 2, 3]),
        clientPrivateKey: Uint8List.fromList([4, 5, 6]),
        caCertificate: Uint8List.fromList([7, 8, 9]),
        serverHost: 'localhost',
        serverPort: 8443,
      );
    });

    group('isValid', () {
      test('should return true when all certificates present', () {
        expect(config.isValid, true);
      });

      test('should return false with empty certificate', () {
        final invalid = MtlsConfig(
          clientCertificate: Uint8List(0),
          clientPrivateKey: Uint8List.fromList([1]),
          caCertificate: Uint8List.fromList([1]),
        );

        expect(invalid.isValid, false);
      });

      test('should return false with empty key', () {
        final invalid = MtlsConfig(
          clientCertificate: Uint8List.fromList([1]),
          clientPrivateKey: Uint8List(0),
          caCertificate: Uint8List.fromList([1]),
        );

        expect(invalid.isValid, false);
      });

      test('should return false with empty CA', () {
        final invalid = MtlsConfig(
          clientCertificate: Uint8List.fromList([1]),
          clientPrivateKey: Uint8List.fromList([1]),
          caCertificate: Uint8List(0),
        );

        expect(invalid.isValid, false);
      });
    });

    group('getWebSocketUrl', () {
      test('should return correct wss URL', () {
        final url = config.getWebSocketUrl();

        expect(url, 'wss://localhost:8443/ws');
      });

      test('should use custom path', () {
        final url = config.getWebSocketUrl(path: '/custom');

        expect(url, 'wss://localhost:8443/custom');
      });

      test('should throw if host not configured', () {
        final noHost = MtlsConfig(
          clientCertificate: Uint8List.fromList([1]),
          clientPrivateKey: Uint8List.fromList([1]),
          caCertificate: Uint8List.fromList([1]),
        );

        expect(() => noHost.getWebSocketUrl(), throwsStateError);
      });

      test('should throw if port not configured', () {
        final noPort = MtlsConfig(
          clientCertificate: Uint8List.fromList([1]),
          clientPrivateKey: Uint8List.fromList([1]),
          caCertificate: Uint8List.fromList([1]),
          serverHost: 'localhost',
        );

        expect(() => noPort.getWebSocketUrl(), throwsStateError);
      });
    });

    group('toString', () {
      test('should include relevant info', () {
        final str = config.toString();

        expect(str, contains('localhost'));
        expect(str, contains('8443'));
        expect(str, contains('certSize: 3'));
        expect(str, contains('keySize: 3'));
        expect(str, contains('caSize: 3'));
      });
    });

    group('password', () {
      test('should store password', () {
        final withPassword = MtlsConfig(
          clientCertificate: Uint8List.fromList([1]),
          clientPrivateKey: Uint8List.fromList([1]),
          caCertificate: Uint8List.fromList([1]),
          password: 'secret',
        );

        expect(withPassword.password, 'secret');
      });
    });
  });

  group('MtlsConfigException', () {
    test('should format without cause', () {
      const exception = MtlsConfigException('Test error');

      expect(exception.toString(), 'MtlsConfigException: Test error');
    });

    test('should format with cause', () {
      const exception = MtlsConfigException(
        'Test error',
        'underlying cause',
      );

      expect(
        exception.toString(),
        'MtlsConfigException: Test error (caused by: underlying cause)',
      );
    });

    test('should store message and cause', () {
      const exception = MtlsConfigException('message', 'cause');

      expect(exception.message, 'message');
      expect(exception.cause, 'cause');
    });
  });
}
