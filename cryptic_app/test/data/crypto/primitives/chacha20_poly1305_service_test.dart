// test/data/crypto/primitives/chacha20_poly1305_service_test.dart
//
// Unit tests for ChaCha20-Poly1305 AEAD encryption service

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cryptic_app/core/errors/app_exceptions.dart';
import 'package:cryptic_app/data/crypto/primitives/chacha20_poly1305_service.dart';

void main() {
  late ChaCha20Poly1305Service chacha;

  setUp(() {
    chacha = ChaCha20Poly1305Service();
  });

  group('ChaCha20Poly1305Service', () {
    group('generateNonce', () {
      test('generates 12-byte nonce', () {
        final nonce = chacha.generateNonce();

        expect(nonce.length, 12);
      });

      test('generates unique nonces', () {
        final nonce1 = chacha.generateNonce();
        final nonce2 = chacha.generateNonce();

        expect(nonce1, isNot(equals(nonce2)));
      });
    });

    group('encrypt', () {
      test('encrypts plaintext with named parameters', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final plaintext = Uint8List.fromList('Hello, World!'.codeUnits);

        final result = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
        );

        expect(result.ciphertext.length, plaintext.length);
        expect(result.nonce.length, 12);
        expect(result.tag.length, 16);
        expect(result.ciphertext, isNot(equals(plaintext)));
      });

      test('uses provided nonce', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final nonce = Uint8List(12)..fillRange(0, 12, 0x01);
        final plaintext = Uint8List.fromList('Hello'.codeUnits);

        final result = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
          nonce: nonce,
        );

        expect(result.nonce, equals(nonce));
      });

      test('produces deterministic ciphertext with same key and nonce',
          () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final nonce = Uint8List(12)..fillRange(0, 12, 0x01);
        final plaintext = Uint8List.fromList('Hello'.codeUnits);

        final result1 = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
          nonce: nonce,
        );

        final result2 = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
          nonce: nonce,
        );

        expect(result1.ciphertext, equals(result2.ciphertext));
        expect(result1.tag, equals(result2.tag));
      });

      test('ciphertextWithTag returns ciphertext with appended tag', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final plaintext = Uint8List.fromList('Hello'.codeUnits);

        final result = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
        );

        expect(
          result.ciphertextWithTag.length,
          result.ciphertext.length + result.tag.length,
        );

        // Verify tag is appended correctly
        final expectedCombined = Uint8List(result.ciphertext.length + 16);
        expectedCombined.setRange(0, result.ciphertext.length, result.ciphertext);
        expectedCombined.setRange(
          result.ciphertext.length,
          expectedCombined.length,
          result.tag,
        );
        expect(result.ciphertextWithTag, equals(expectedCombined));
      });

      test('throws on invalid key length', () async {
        final invalidKey = Uint8List(16); // Should be 32 bytes
        final plaintext = Uint8List.fromList('Hello'.codeUnits);

        expect(
          () => chacha.encrypt(plaintext: plaintext, key: invalidKey),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('throws on invalid nonce length', () async {
        final key = Uint8List(32);
        final invalidNonce = Uint8List(8); // Should be 12 bytes
        final plaintext = Uint8List.fromList('Hello'.codeUnits);

        expect(
          () => chacha.encrypt(
            plaintext: plaintext,
            key: key,
            nonce: invalidNonce,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('can encrypt empty plaintext', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final plaintext = Uint8List(0);

        final result = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
        );

        expect(result.ciphertext.length, 0);
        expect(result.tag.length, 16);
      });
    });

    group('decrypt', () {
      test('decrypts ciphertext correctly', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final plaintext = Uint8List.fromList('Hello, World!'.codeUnits);

        final encrypted = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
        );

        final decrypted = await chacha.decrypt(
          ciphertext: encrypted.ciphertext,
          key: key,
          nonce: encrypted.nonce,
          tag: encrypted.tag,
        );

        expect(decrypted, equals(plaintext));
      });

      test('decrypts ciphertext with appended tag', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final plaintext = Uint8List.fromList('Hello, World!'.codeUnits);

        final encrypted = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
        );

        // Decrypt using ciphertextWithTag (tag=null means extract from ciphertext)
        final decrypted = await chacha.decrypt(
          ciphertext: encrypted.ciphertextWithTag,
          key: key,
          nonce: encrypted.nonce,
        );

        expect(decrypted, equals(plaintext));
      });

      test('throws on authentication failure', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final plaintext = Uint8List.fromList('Hello'.codeUnits);

        final encrypted = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
        );

        // Modify ciphertext
        encrypted.ciphertext[0] ^= 0xFF;

        expect(
          () => chacha.decrypt(
            ciphertext: encrypted.ciphertext,
            key: key,
            nonce: encrypted.nonce,
            tag: encrypted.tag,
          ),
          throwsA(isA<DecryptionException>()),
        );
      });

      test('throws with wrong key', () async {
        final key1 = Uint8List(32)..fillRange(0, 32, 0x42);
        final key2 = Uint8List(32)..fillRange(0, 32, 0x43);
        final plaintext = Uint8List.fromList('Hello'.codeUnits);

        final encrypted = await chacha.encrypt(
          plaintext: plaintext,
          key: key1,
        );

        expect(
          () => chacha.decrypt(
            ciphertext: encrypted.ciphertext,
            key: key2,
            nonce: encrypted.nonce,
            tag: encrypted.tag,
          ),
          throwsA(isA<DecryptionException>()),
        );
      });

      test('throws on invalid key length', () async {
        final invalidKey = Uint8List(16);
        final ciphertext = Uint8List(10);
        final nonce = Uint8List(12);
        final tag = Uint8List(16);

        expect(
          () => chacha.decrypt(
            ciphertext: ciphertext,
            key: invalidKey,
            nonce: nonce,
            tag: tag,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('throws on invalid nonce length', () async {
        final key = Uint8List(32);
        final ciphertext = Uint8List(10);
        final invalidNonce = Uint8List(8);
        final tag = Uint8List(16);

        expect(
          () => chacha.decrypt(
            ciphertext: ciphertext,
            key: key,
            nonce: invalidNonce,
            tag: tag,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('throws on invalid tag length when explicitly provided', () async {
        final key = Uint8List(32);
        final ciphertext = Uint8List(10);
        final nonce = Uint8List(12);
        final invalidTag = Uint8List(8);

        expect(
          () => chacha.decrypt(
            ciphertext: ciphertext,
            key: key,
            nonce: nonce,
            tag: invalidTag,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });
    });

    group('decryptWithAppendedTag', () {
      test('decrypts ciphertext with tag appended', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final plaintext = Uint8List.fromList('Hello, World!'.codeUnits);

        final encrypted = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
        );

        final decrypted = await chacha.decryptWithAppendedTag(
          ciphertextWithTag: encrypted.ciphertextWithTag,
          key: key,
          nonce: encrypted.nonce,
        );

        expect(decrypted, equals(plaintext));
      });

      test('throws on ciphertext too short', () async {
        final key = Uint8List(32);
        final nonce = Uint8List(12);
        final tooShort = Uint8List(10); // Less than 16-byte tag

        expect(
          () => chacha.decryptWithAppendedTag(
            ciphertextWithTag: tooShort,
            key: key,
            nonce: nonce,
          ),
          throwsA(isA<DecryptionException>()),
        );
      });
    });

    group('round trip', () {
      test('handles various message sizes', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);

        final sizes = [0, 1, 15, 16, 17, 100, 1000, 10000];

        for (final size in sizes) {
          final plaintext = Uint8List(size);
          for (var i = 0; i < size; i++) {
            plaintext[i] = i % 256;
          }

          final encrypted = await chacha.encrypt(
            plaintext: plaintext,
            key: key,
          );

          final decrypted = await chacha.decrypt(
            ciphertext: encrypted.ciphertext,
            key: key,
            nonce: encrypted.nonce,
            tag: encrypted.tag,
          );

          expect(
            decrypted,
            equals(plaintext),
            reason: 'Failed for size $size',
          );
        }
      });

      test('handles associated data correctly', () async {
        final key = Uint8List(32)..fillRange(0, 32, 0x42);
        final plaintext = Uint8List.fromList('Secret'.codeUnits);
        final aad = Uint8List.fromList('Header'.codeUnits);

        final encrypted = await chacha.encrypt(
          plaintext: plaintext,
          key: key,
          associatedData: aad,
        );

        // Decrypt with same AAD succeeds
        final decrypted = await chacha.decrypt(
          ciphertext: encrypted.ciphertext,
          key: key,
          nonce: encrypted.nonce,
          tag: encrypted.tag,
          associatedData: aad,
        );

        expect(decrypted, equals(plaintext));

        // Decrypt with different AAD fails
        final wrongAad = Uint8List.fromList('Wrong'.codeUnits);
        expect(
          () => chacha.decrypt(
            ciphertext: encrypted.ciphertext,
            key: key,
            nonce: encrypted.nonce,
            tag: encrypted.tag,
            associatedData: wrongAad,
          ),
          throwsA(isA<DecryptionException>()),
        );
      });
    });
  });
}
