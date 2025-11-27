// test/data/crypto/x3dh/x3dh_engine_test.dart
//
// Unit tests for X3DH key agreement engine

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cryptic_app/data/crypto/keys/key_bundle.dart';
import 'package:cryptic_app/data/crypto/keys/key_generator.dart';
import 'package:cryptic_app/data/crypto/x3dh/x3dh_engine.dart';

void main() {
  late X3dhEngine x3dh;
  late KeyGenerator keyGen;

  setUp(() {
    x3dh = X3dhEngine();
    keyGen = KeyGenerator();
  });

  group('X3dhEngine', () {
    group('key agreement', () {
      test('Alice and Bob derive same session key', () async {
        // Generate Alice's keys
        final aliceBundle = await keyGen.generateFullKeyBundle();

        // Generate Bob's keys
        final bobBundle = await keyGen.generateFullKeyBundle();

        // Alice sends first message to Bob
        final plaintext = Uint8List.fromList('Hello Bob!'.codeUnits);

        final aliceResult = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        // Bob receives and decrypts
        final bobResult = await x3dh.receiverDecrypt(
          receiverKeys: bobBundle,
          messageBlob: aliceResult.messageBlob,
        );

        // Verify same session key
        expect(aliceResult.sessionKey, equals(bobResult.sessionKey));

        // Verify message decrypted correctly
        expect(bobResult.plaintext, equals(plaintext));
      });

      test('produces unique session keys for different sessions', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        final plaintext = Uint8List.fromList('Test'.codeUnits);

        final result1 = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        // Generate fresh ephemeral key for second session
        final result2 = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        // Different ephemeral keys = different session keys
        expect(result1.sessionKey, isNot(equals(result2.sessionKey)));
      });

      test('returns correct ephemeral key pair', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        final plaintext = Uint8List.fromList('Test'.codeUnits);

        final result = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        // Ephemeral public key should match what's in the message blob
        expect(
          result.ephemeralKeyPair.publicKey,
          equals(result.messageBlob.metadata.ephemeralPublic),
        );
      });

      test('receiver gets sender ephemeral public key', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        final plaintext = Uint8List.fromList('Test'.codeUnits);

        final aliceResult = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        final bobResult = await x3dh.receiverDecrypt(
          receiverKeys: bobBundle,
          messageBlob: aliceResult.messageBlob,
        );

        expect(
          bobResult.senderEphemeralPublic,
          equals(aliceResult.ephemeralKeyPair.publicKey),
        );
      });
    });

    group('X3dhMessageBlob', () {
      test('serializes to and from map', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        final plaintext = Uint8List.fromList('Serialize test'.codeUnits);

        final result = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        // Serialize
        final map = result.messageBlob.toMap();

        // Deserialize
        final restored = X3dhMessageBlob.fromMap(map);

        // Verify
        expect(restored.signature, equals(result.messageBlob.signature));
        expect(restored.ciphertext, equals(result.messageBlob.ciphertext));
        expect(restored.nonce, equals(result.messageBlob.nonce));
        expect(
          restored.metadata.messageId,
          equals(result.messageBlob.metadata.messageId),
        );
      });

      test('deserialized blob can be decrypted', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        final plaintext = Uint8List.fromList('Round trip'.codeUnits);

        final aliceResult = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        // Serialize and deserialize
        final map = aliceResult.messageBlob.toMap();
        final restored = X3dhMessageBlob.fromMap(map);

        // Decrypt with restored blob
        final bobResult = await x3dh.receiverDecrypt(
          receiverKeys: bobBundle,
          messageBlob: restored,
        );

        expect(bobResult.plaintext, equals(plaintext));
      });
    });

    group('X3dhMetadata', () {
      test('toBytes produces consistent output', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        final plaintext = Uint8List.fromList('Metadata test'.codeUnits);

        final result = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        final bytes1 = result.messageBlob.metadata.toBytes();
        final bytes2 = result.messageBlob.metadata.toBytes();

        expect(bytes1, equals(bytes2));
      });

      test('metadata includes correct version', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        final plaintext = Uint8List.fromList('Version check'.codeUnits);

        final result = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: plaintext,
        );

        expect(result.messageBlob.metadata.version, 1);
        expect(result.messageBlob.metadata.type, 'X3DH_INIT');
      });
    });

    group('edge cases', () {
      test('handles empty plaintext', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        final emptyPlaintext = Uint8List(0);

        final aliceResult = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: emptyPlaintext,
        );

        final bobResult = await x3dh.receiverDecrypt(
          receiverKeys: bobBundle,
          messageBlob: aliceResult.messageBlob,
        );

        expect(bobResult.plaintext, equals(emptyPlaintext));
        expect(bobResult.plaintext.length, 0);
      });

      test('handles large plaintext', () async {
        final aliceBundle = await keyGen.generateFullKeyBundle();
        final bobBundle = await keyGen.generateFullKeyBundle();

        // 10KB message
        final largePlaintext = Uint8List(10240);
        for (var i = 0; i < largePlaintext.length; i++) {
          largePlaintext[i] = i % 256;
        }

        final aliceResult = await x3dh.senderInit(
          senderKeys: aliceBundle,
          recipientBundle: bobBundle.toPublicBundle('bob'),
          plaintext: largePlaintext,
        );

        final bobResult = await x3dh.receiverDecrypt(
          receiverKeys: bobBundle,
          messageBlob: aliceResult.messageBlob,
        );

        expect(bobResult.plaintext, equals(largePlaintext));
      });
    });
  });
}
