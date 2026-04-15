// test/core/constants/crypto_constants_test.dart
//
// Unit tests for crypto constants
//

import 'package:cryptic_app/core/constants/crypto_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CryptoConstants', () {
    test('Ed25519 constants should match Signal spec', () {
      expect(CryptoConstants.ed25519PublicKeySize, equals(32));
      expect(CryptoConstants.ed25519PrivateKeySize, equals(64));
      expect(CryptoConstants.ed25519SignatureSize, equals(64));
    });

    test('X25519 constants should match Signal spec', () {
      expect(CryptoConstants.x25519KeySize, equals(32));
      expect(CryptoConstants.x25519SharedSecretSize, equals(32));
    });

    test('ChaCha20-Poly1305 constants should be correct', () {
      expect(CryptoConstants.chaChaKeySize, equals(32));
      expect(CryptoConstants.chaChaNonceSize, equals(12));
      expect(CryptoConstants.chaChaTagSize, equals(16));
    });

    test('HKDF constants should be correct', () {
      expect(CryptoConstants.hkdfOutputSize, equals(32));
      expect(CryptoConstants.hkdfSaltSize, equals(32));
    });

    test('info strings should be non-empty', () {
      expect(CryptoConstants.x3dhInfo, isNotEmpty);
      expect(CryptoConstants.ratchetChainInfo, isNotEmpty);
      expect(CryptoConstants.ratchetMessageInfo, isNotEmpty);
    });

    test('skip limits should be reasonable', () {
      // These prevent memory exhaustion attacks
      expect(CryptoConstants.maxSkippedMessageKeys, greaterThan(0));
      expect(CryptoConstants.maxSkippedMessageKeys, lessThanOrEqualTo(2000));
      expect(CryptoConstants.maxSkipPerStep, greaterThan(0));
      expect(CryptoConstants.maxSkipPerStep, lessThanOrEqualTo(200));
    });
  });
}
