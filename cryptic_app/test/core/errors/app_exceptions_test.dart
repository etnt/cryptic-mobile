// test/core/errors/app_exceptions_test.dart
//
// Unit tests for custom exceptions
//

import 'package:cryptic_app/core/errors/app_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CryptoException', () {
    test('should store message', () {
      const exception = CryptoException('Crypto failed');
      expect(exception.message, equals('Crypto failed'));
    });

    test('toString should include type and message', () {
      const exception = CryptoException('Crypto failed');
      expect(exception.toString(), contains('CryptoException'));
      expect(exception.toString(), contains('Crypto failed'));
    });
  });

  group('InvalidKeyException', () {
    test('should be a CryptoException', () {
      const exception = InvalidKeyException('Bad key');
      expect(exception, isA<CryptoException>());
    });
  });

  group('SignatureVerificationException', () {
    test('should have default message', () {
      const exception = SignatureVerificationException();
      expect(exception.message, contains('Signature verification'));
    });

    test('should accept custom message', () {
      const exception = SignatureVerificationException('Custom message');
      expect(exception.message, equals('Custom message'));
    });
  });

  group('DecryptionException', () {
    test('should have default message', () {
      const exception = DecryptionException();
      expect(exception.message, contains('decrypt'));
    });
  });

  group('StorageException', () {
    test('should store message', () {
      const exception = StorageException('Storage failed');
      expect(exception.message, equals('Storage failed'));
    });
  });

  group('KeyNotFoundException', () {
    test('should include key type in message', () {
      const exception = KeyNotFoundException('identity_key');
      expect(exception.message, contains('identity_key'));
    });
  });

  group('NetworkException', () {
    test('should store message', () {
      const exception = NetworkException('Network failed');
      expect(exception.message, equals('Network failed'));
    });
  });

  group('ConnectionException', () {
    test('should be a NetworkException', () {
      const exception = ConnectionException();
      expect(exception, isA<NetworkException>());
    });

    test('should have default message', () {
      const exception = ConnectionException();
      expect(exception.message, contains('connect'));
    });
  });

  group('ServerException', () {
    test('should store error code', () {
      const exception = ServerException('Server error', errorCode: 'E001');
      expect(exception.errorCode, equals('E001'));
    });

    test('error code should be optional', () {
      const exception = ServerException('Server error');
      expect(exception.errorCode, isNull);
    });
  });

  group('ProtocolException', () {
    test('should store message', () {
      const exception = ProtocolException('Protocol failed');
      expect(exception.message, equals('Protocol failed'));
    });
  });

  group('NoSessionException', () {
    test('should include peer in message', () {
      const exception = NoSessionException('alice');
      expect(exception.message, contains('alice'));
    });
  });

  group('MessageOrderException', () {
    test('should have default message', () {
      const exception = MessageOrderException();
      expect(exception.message, contains('order'));
    });
  });
}
