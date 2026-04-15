// test/data/crypto/primitives/ed25519_service_test.dart
//
// Unit tests for Ed25519 digital signature service

import 'dart:typed_data';

import 'package:cryptic_app/core/errors/app_exceptions.dart';
import 'package:cryptic_app/data/crypto/primitives/ed25519_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Ed25519Service ed25519;

  setUp(() {
    ed25519 = Ed25519Service();
  });

  group('Ed25519Service', () {
    group('generateKeyPair', () {
      test('generates valid key pair', () async {
        final keyPair = await ed25519.generateKeyPair();

        expect(keyPair.publicKey.length, 32);
        expect(keyPair.privateKey.length, 64);
        expect(keyPair.isValid, true);
      });

      test('generates unique key pairs', () async {
        final keyPair1 = await ed25519.generateKeyPair();
        final keyPair2 = await ed25519.generateKeyPair();

        expect(keyPair1.publicKey, isNot(equals(keyPair2.publicKey)));
        expect(keyPair1.privateKey, isNot(equals(keyPair2.privateKey)));
      });

      test('private key contains public key suffix', () async {
        final keyPair = await ed25519.generateKeyPair();

        // Ed25519 private key format: seed (32 bytes) || public key (32 bytes)
        final publicKeySuffix = keyPair.privateKey.sublist(32, 64);
        expect(publicKeySuffix, equals(keyPair.publicKey));
      });
    });

    group('sign', () {
      test('signs message with valid signature', () async {
        final keyPair = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello, World!'.codeUnits);

        final signature = await ed25519.sign(
          message: message,
          privateKey: keyPair.privateKey,
        );

        expect(signature.length, 64);
      });

      test('produces deterministic signatures', () async {
        final keyPair = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello, World!'.codeUnits);

        final signature1 = await ed25519.sign(
          message: message,
          privateKey: keyPair.privateKey,
        );
        final signature2 = await ed25519.sign(
          message: message,
          privateKey: keyPair.privateKey,
        );

        expect(signature1, equals(signature2));
      });

      test('produces different signatures for different messages', () async {
        final keyPair = await ed25519.generateKeyPair();
        final message1 = Uint8List.fromList('Hello'.codeUnits);
        final message2 = Uint8List.fromList('World'.codeUnits);

        final signature1 = await ed25519.sign(
          message: message1,
          privateKey: keyPair.privateKey,
        );
        final signature2 = await ed25519.sign(
          message: message2,
          privateKey: keyPair.privateKey,
        );

        expect(signature1, isNot(equals(signature2)));
      });

      test('throws on invalid private key length', () async {
        final message = Uint8List.fromList('Hello'.codeUnits);
        final invalidPrivateKey = Uint8List(32); // Should be 64 bytes

        expect(
          () => ed25519.sign(message: message, privateKey: invalidPrivateKey),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('can sign empty message', () async {
        final keyPair = await ed25519.generateKeyPair();
        final emptyMessage = Uint8List(0);

        final signature = await ed25519.sign(
          message: emptyMessage,
          privateKey: keyPair.privateKey,
        );

        expect(signature.length, 64);
      });
    });

    group('verify', () {
      test('verifies valid signature', () async {
        final keyPair = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello, World!'.codeUnits);

        final signature = await ed25519.sign(
          message: message,
          privateKey: keyPair.privateKey,
        );

        final isValid = await ed25519.verify(
          message: message,
          signature: signature,
          publicKey: keyPair.publicKey,
        );

        expect(isValid, true);
      });

      test('rejects invalid signature', () async {
        final keyPair = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello, World!'.codeUnits);

        final invalidSignature = Uint8List(64); // All zeros

        final isValid = await ed25519.verify(
          message: message,
          signature: invalidSignature,
          publicKey: keyPair.publicKey,
        );

        expect(isValid, false);
      });

      test('rejects signature with wrong public key', () async {
        final keyPair1 = await ed25519.generateKeyPair();
        final keyPair2 = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello, World!'.codeUnits);

        final signature = await ed25519.sign(
          message: message,
          privateKey: keyPair1.privateKey,
        );

        final isValid = await ed25519.verify(
          message: message,
          signature: signature,
          publicKey: keyPair2.publicKey,
        );

        expect(isValid, false);
      });

      test('rejects signature with modified message', () async {
        final keyPair = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello, World!'.codeUnits);

        final signature = await ed25519.sign(
          message: message,
          privateKey: keyPair.privateKey,
        );

        final modifiedMessage = Uint8List.fromList('Hello, World?'.codeUnits);

        final isValid = await ed25519.verify(
          message: modifiedMessage,
          signature: signature,
          publicKey: keyPair.publicKey,
        );

        expect(isValid, false);
      });

      test('throws on invalid public key length', () async {
        final message = Uint8List.fromList('Hello'.codeUnits);
        final signature = Uint8List(64);
        final invalidPublicKey = Uint8List(16); // Should be 32 bytes

        expect(
          () => ed25519.verify(
            message: message,
            signature: signature,
            publicKey: invalidPublicKey,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('returns false for invalid signature length', () async {
        final keyPair = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello'.codeUnits);
        final shortSignature = Uint8List(32); // Should be 64 bytes

        final isValid = await ed25519.verify(
          message: message,
          signature: shortSignature,
          publicKey: keyPair.publicKey,
        );

        expect(isValid, false);
      });
    });

    group('verifyOrThrow', () {
      test('succeeds for valid signature', () async {
        final keyPair = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello, World!'.codeUnits);

        final signature = await ed25519.sign(
          message: message,
          privateKey: keyPair.privateKey,
        );

        await expectLater(
          ed25519.verifyOrThrow(
            message: message,
            signature: signature,
            publicKey: keyPair.publicKey,
          ),
          completes,
        );
      });

      test('throws SignatureVerificationException for invalid signature',
          () async {
        final keyPair = await ed25519.generateKeyPair();
        final message = Uint8List.fromList('Hello'.codeUnits);
        final invalidSignature = Uint8List(64);

        expect(
          () => ed25519.verifyOrThrow(
            message: message,
            signature: invalidSignature,
            publicKey: keyPair.publicKey,
          ),
          throwsA(isA<SignatureVerificationException>()),
        );
      });
    });
  });
}
