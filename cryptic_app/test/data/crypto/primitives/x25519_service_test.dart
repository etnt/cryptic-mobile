// test/data/crypto/primitives/x25519_service_test.dart
//
// Unit tests for X25519 Diffie-Hellman service

import 'dart:typed_data';

import 'package:cryptic_app/core/errors/app_exceptions.dart';
import 'package:cryptic_app/data/crypto/primitives/x25519_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late X25519Service x25519;

  setUp(() {
    x25519 = X25519Service();
  });

  group('X25519Service', () {
    group('generateKeyPair', () {
      test('generates valid key pair', () async {
        final keyPair = await x25519.generateKeyPair();

        expect(keyPair.publicKey.length, 32);
        expect(keyPair.privateKey.length, 32);
        expect(keyPair.isValid, true);
      });

      test('generates unique key pairs', () async {
        final keyPair1 = await x25519.generateKeyPair();
        final keyPair2 = await x25519.generateKeyPair();

        expect(keyPair1.publicKey, isNot(equals(keyPair2.publicKey)));
        expect(keyPair1.privateKey, isNot(equals(keyPair2.privateKey)));
      });
    });

    group('sharedSecret', () {
      test('computes shared secret with named parameters', () async {
        final aliceKeyPair = await x25519.generateKeyPair();
        final bobKeyPair = await x25519.generateKeyPair();

        final aliceSharedSecret = await x25519.sharedSecret(
          privateKey: aliceKeyPair.privateKey,
          publicKey: bobKeyPair.publicKey,
        );

        expect(aliceSharedSecret.length, 32);
      });

      test('ECDH produces same shared secret on both sides', () async {
        final aliceKeyPair = await x25519.generateKeyPair();
        final bobKeyPair = await x25519.generateKeyPair();

        final aliceSharedSecret = await x25519.sharedSecret(
          privateKey: aliceKeyPair.privateKey,
          publicKey: bobKeyPair.publicKey,
        );

        final bobSharedSecret = await x25519.sharedSecret(
          privateKey: bobKeyPair.privateKey,
          publicKey: aliceKeyPair.publicKey,
        );

        expect(aliceSharedSecret, equals(bobSharedSecret));
      });

      test('different key pairs produce different shared secrets', () async {
        final alice = await x25519.generateKeyPair();
        final bob = await x25519.generateKeyPair();
        final charlie = await x25519.generateKeyPair();

        final aliceBobSecret = await x25519.sharedSecret(
          privateKey: alice.privateKey,
          publicKey: bob.publicKey,
        );

        final aliceCharlieSecret = await x25519.sharedSecret(
          privateKey: alice.privateKey,
          publicKey: charlie.publicKey,
        );

        expect(aliceBobSecret, isNot(equals(aliceCharlieSecret)));
      });

      test('shared secret is deterministic', () async {
        final alice = await x25519.generateKeyPair();
        final bob = await x25519.generateKeyPair();

        final secret1 = await x25519.sharedSecret(
          privateKey: alice.privateKey,
          publicKey: bob.publicKey,
        );

        final secret2 = await x25519.sharedSecret(
          privateKey: alice.privateKey,
          publicKey: bob.publicKey,
        );

        expect(secret1, equals(secret2));
      });

      test('throws on invalid private key length', () async {
        final bobKeyPair = await x25519.generateKeyPair();
        final invalidPrivateKey = Uint8List(16); // Should be 32 bytes

        expect(
          () => x25519.sharedSecret(
            privateKey: invalidPrivateKey,
            publicKey: bobKeyPair.publicKey,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('throws on invalid public key length', () async {
        final aliceKeyPair = await x25519.generateKeyPair();
        final invalidPublicKey = Uint8List(16); // Should be 32 bytes

        expect(
          () => x25519.sharedSecret(
            privateKey: aliceKeyPair.privateKey,
            publicKey: invalidPublicKey,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });
    });

    group('computeSharedSecret (alias)', () {
      test('works as alias for sharedSecret', () async {
        final alice = await x25519.generateKeyPair();
        final bob = await x25519.generateKeyPair();

        final secret1 = await x25519.sharedSecret(
          privateKey: alice.privateKey,
          publicKey: bob.publicKey,
        );

        final secret2 = await x25519.computeSharedSecret(
          privateKey: alice.privateKey,
          publicKey: bob.publicKey,
        );

        expect(secret1, equals(secret2));
      });
    });

    group('sharedSecretFromKeyPair', () {
      test('computes shared secret from key pair object', () async {
        final alice = await x25519.generateKeyPair();
        final bob = await x25519.generateKeyPair();

        final secretFromKeyPair = await x25519.sharedSecretFromKeyPair(
          alice,
          bob.publicKey,
        );

        final secretDirect = await x25519.sharedSecret(
          privateKey: alice.privateKey,
          publicKey: bob.publicKey,
        );

        expect(secretFromKeyPair, equals(secretDirect));
      });
    });
  });
}
