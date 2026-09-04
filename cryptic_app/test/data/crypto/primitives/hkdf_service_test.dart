// test/data/crypto/primitives/hkdf_service_test.dart
//
// Unit tests for HKDF key derivation service

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cryptic_app/core/errors/app_exceptions.dart';
import 'package:cryptic_app/data/crypto/primitives/hkdf_service.dart';

void main() {
  late HkdfService hkdf;

  setUp(() {
    hkdf = HkdfService();
  });

  group('HkdfService', () {
    group('deriveKey', () {
      test('derives 32-byte key by default', () async {
        final ikm = Uint8List(32)..fillRange(0, 32, 0x42);

        final key = await hkdf.deriveKey(
          inputKeyMaterial: ikm,
          info: 'test',
        );

        expect(key.length, 32);
      });

      test('derives key with custom output length', () async {
        final ikm = Uint8List(32)..fillRange(0, 32, 0x42);

        final key = await hkdf.deriveKey(
          inputKeyMaterial: ikm,
          info: 'test',
          outputLength: 64,
        );

        expect(key.length, 64);
      });

      test('produces deterministic output', () async {
        final ikm = Uint8List(32)..fillRange(0, 32, 0x42);

        final key1 = await hkdf.deriveKey(
          inputKeyMaterial: ikm,
          info: 'test',
        );

        final key2 = await hkdf.deriveKey(
          inputKeyMaterial: ikm,
          info: 'test',
        );

        expect(key1, equals(key2));
      });

      test('different info produces different keys', () async {
        final ikm = Uint8List(32)..fillRange(0, 32, 0x42);

        final key1 = await hkdf.deriveKey(
          inputKeyMaterial: ikm,
          info: 'context1',
        );

        final key2 = await hkdf.deriveKey(
          inputKeyMaterial: ikm,
          info: 'context2',
        );

        expect(key1, isNot(equals(key2)));
      });

      test('different salt produces different keys', () async {
        final ikm = Uint8List(32)..fillRange(0, 32, 0x42);
        final salt1 = Uint8List(32)..fillRange(0, 32, 0x01);
        final salt2 = Uint8List(32)..fillRange(0, 32, 0x02);

        final key1 = await hkdf.deriveKey(
          inputKeyMaterial: ikm,
          salt: salt1,
          info: 'test',
        );

        final key2 = await hkdf.deriveKey(
          inputKeyMaterial: ikm,
          salt: salt2,
          info: 'test',
        );

        expect(key1, isNot(equals(key2)));
      });

      test('throws on empty input key material', () async {
        final emptyIkm = Uint8List(0);

        expect(
          () => hkdf.deriveKey(inputKeyMaterial: emptyIkm, info: 'test'),
          throwsA(isA<CryptoException>()),
        );
      });
    });

    group('deriveX3dhSecret', () {
      test('combines multiple DH outputs', () async {
        final dh1 = Uint8List(32)..fillRange(0, 32, 0x01);
        final dh2 = Uint8List(32)..fillRange(0, 32, 0x02);
        final dh3 = Uint8List(32)..fillRange(0, 32, 0x03);

        final secret = await hkdf.deriveX3dhSecret(
          dhOutputs: [dh1, dh2, dh3],
        );

        expect(secret.length, 32);
      });

      test('handles 4 DH outputs (with one-time prekey)', () async {
        final dh1 = Uint8List(32)..fillRange(0, 32, 0x01);
        final dh2 = Uint8List(32)..fillRange(0, 32, 0x02);
        final dh3 = Uint8List(32)..fillRange(0, 32, 0x03);
        final dh4 = Uint8List(32)..fillRange(0, 32, 0x04);

        final secret = await hkdf.deriveX3dhSecret(
          dhOutputs: [dh1, dh2, dh3, dh4],
        );

        expect(secret.length, 32);
      });

      test('produces deterministic output', () async {
        final dh1 = Uint8List(32)..fillRange(0, 32, 0x01);
        final dh2 = Uint8List(32)..fillRange(0, 32, 0x02);
        final dh3 = Uint8List(32)..fillRange(0, 32, 0x03);

        final secret1 = await hkdf.deriveX3dhSecret(
          dhOutputs: [dh1, dh2, dh3],
        );

        final secret2 = await hkdf.deriveX3dhSecret(
          dhOutputs: [dh1, dh2, dh3],
        );

        expect(secret1, equals(secret2));
      });

      test('order of DH outputs matters', () async {
        final dh1 = Uint8List(32)..fillRange(0, 32, 0x01);
        final dh2 = Uint8List(32)..fillRange(0, 32, 0x02);
        final dh3 = Uint8List(32)..fillRange(0, 32, 0x03);

        final secret1 = await hkdf.deriveX3dhSecret(
          dhOutputs: [dh1, dh2, dh3],
        );

        final secret2 = await hkdf.deriveX3dhSecret(
          dhOutputs: [dh3, dh2, dh1],
        );

        expect(secret1, isNot(equals(secret2)));
      });

      test('uses custom info string', () async {
        final dh1 = Uint8List(32)..fillRange(0, 32, 0x01);
        final dh2 = Uint8List(32)..fillRange(0, 32, 0x02);
        final dh3 = Uint8List(32)..fillRange(0, 32, 0x03);

        final secret1 = await hkdf.deriveX3dhSecret(
          dhOutputs: [dh1, dh2, dh3],
        );

        final secret2 = await hkdf.deriveX3dhSecret(
          dhOutputs: [dh1, dh2, dh3],
          info: 'Different',
        );

        expect(secret1, isNot(equals(secret2)));
      });
    });

    group('deriveRatchetKeys', () {
      test('produces root key and chain key', () async {
        final rootKey = Uint8List(32)..fillRange(0, 32, 0x01);
        final dhOutput = Uint8List(32)..fillRange(0, 32, 0x02);

        final (newRootKey, chainKey) = await hkdf.deriveRatchetKeys(
          rootKey: rootKey,
          dhOutput: dhOutput,
        );

        expect(newRootKey.length, 32);
        expect(chainKey.length, 32);
        expect(newRootKey, isNot(equals(chainKey)));
      });

      test('produces deterministic output', () async {
        final rootKey = Uint8List(32)..fillRange(0, 32, 0x01);
        final dhOutput = Uint8List(32)..fillRange(0, 32, 0x02);

        final (rk1, ck1) = await hkdf.deriveRatchetKeys(
          rootKey: rootKey,
          dhOutput: dhOutput,
        );

        final (rk2, ck2) = await hkdf.deriveRatchetKeys(
          rootKey: rootKey,
          dhOutput: dhOutput,
        );

        expect(rk1, equals(rk2));
        expect(ck1, equals(ck2));
      });

      test('throws on invalid root key length', () async {
        final invalidRootKey = Uint8List(16);
        final dhOutput = Uint8List(32);

        expect(
          () => hkdf.deriveRatchetKeys(
            rootKey: invalidRootKey,
            dhOutput: dhOutput,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('throws on invalid DH output length', () async {
        final rootKey = Uint8List(32);
        final invalidDhOutput = Uint8List(16);

        expect(
          () => hkdf.deriveRatchetKeys(
            rootKey: rootKey,
            dhOutput: invalidDhOutput,
          ),
          throwsA(isA<InvalidKeyException>()),
        );
      });
    });

    group('deriveMessageKey', () {
      test('produces new chain key and message key', () async {
        final chainKey = Uint8List(32)..fillRange(0, 32, 0x01);

        final (newChainKey, messageKey) = await hkdf.deriveMessageKey(
          chainKey: chainKey,
        );

        expect(newChainKey.length, 32);
        expect(messageKey.length, 32);
        expect(newChainKey, isNot(equals(messageKey)));
        expect(newChainKey, isNot(equals(chainKey)));
      });

      test('produces deterministic output', () async {
        final chainKey = Uint8List(32)..fillRange(0, 32, 0x01);

        final (ck1, mk1) = await hkdf.deriveMessageKey(chainKey: chainKey);
        final (ck2, mk2) = await hkdf.deriveMessageKey(chainKey: chainKey);

        expect(ck1, equals(ck2));
        expect(mk1, equals(mk2));
      });

      test('chain advances correctly (no cycles)', () async {
        var chainKey = Uint8List(32)..fillRange(0, 32, 0x01);
        final seenChainKeys = <String>{};
        final seenMessageKeys = <String>{};

        // Advance chain 100 times, should never repeat
        for (var i = 0; i < 100; i++) {
          final (newChainKey, messageKey) = await hkdf.deriveMessageKey(
            chainKey: chainKey,
          );

          final ckStr = newChainKey.join(',');
          final mkStr = messageKey.join(',');

          expect(
            seenChainKeys.contains(ckStr),
            false,
            reason: 'Chain key repeated at iteration $i',
          );
          expect(
            seenMessageKeys.contains(mkStr),
            false,
            reason: 'Message key repeated at iteration $i',
          );

          seenChainKeys.add(ckStr);
          seenMessageKeys.add(mkStr);
          chainKey = newChainKey;
        }
      });

      test('throws on invalid chain key length', () async {
        final invalidChainKey = Uint8List(16);

        expect(
          () => hkdf.deriveMessageKey(chainKey: invalidChainKey),
          throwsA(isA<InvalidKeyException>()),
        );
      });
    });

    group('deriveEncryptionComponents', () {
      test('produces encryption key and nonce', () async {
        final messageKey = Uint8List(32)..fillRange(0, 32, 0x01);

        final (encKey, nonce) = await hkdf.deriveEncryptionComponents(
          messageKey: messageKey,
        );

        expect(encKey.length, 32);
        expect(nonce.length, 12);
      });

      test('produces deterministic output', () async {
        final messageKey = Uint8List(32)..fillRange(0, 32, 0x01);

        final (ek1, n1) =
            await hkdf.deriveEncryptionComponents(messageKey: messageKey);
        final (ek2, n2) =
            await hkdf.deriveEncryptionComponents(messageKey: messageKey);

        expect(ek1, equals(ek2));
        expect(n1, equals(n2));
      });

      test('throws on invalid message key length', () async {
        final invalidMessageKey = Uint8List(16);

        expect(
          () => hkdf.deriveEncryptionComponents(messageKey: invalidMessageKey),
          throwsA(isA<InvalidKeyException>()),
        );
      });
    });
  });
}
