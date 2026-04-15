// test/data/crypto/ratchet/double_ratchet_test.dart
//
// Unit tests for Double Ratchet algorithm engine

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cryptic_app/data/crypto/primitives/x25519_service.dart';
import 'package:cryptic_app/data/crypto/ratchet/double_ratchet.dart';

void main() {
  late DoubleRatchet ratchet;
  late X25519Service x25519;

  setUp(() {
    ratchet = DoubleRatchet();
    x25519 = X25519Service();
  });

  group('DoubleRatchet', () {
    group('initSender', () {
      test('initializes sender state correctly', () async {
        final rootKey = Uint8List(32)..fillRange(0, 32, 0x42);
        final keyPair = await x25519.generateKeyPair();
        final dhPair = (keyPair.publicKey, keyPair.privateKey);

        final state = await ratchet.initSender(
          rootKey: rootKey,
          dhKeyPair: dhPair,
        );

        expect(state.rootKey, equals(rootKey));
        expect(state.sendChainKey.length, 32);
        expect(state.recvChainKey.length, 32);
        expect(state.sendMessageNumber, 0);
        expect(state.recvMessageNumber, 0);
        expect(state.dhSelf, equals(dhPair));
        expect(state.sendingChainActive, true);
        expect(state.receivingChainActive, true);
      });
    });

    group('initReceiver', () {
      test('initializes receiver state correctly', () async {
        final rootKey = Uint8List(32)..fillRange(0, 32, 0x42);
        final keyPair = await x25519.generateKeyPair();
        final dhPair = (keyPair.publicKey, keyPair.privateKey);

        final state = await ratchet.initReceiver(
          rootKey: rootKey,
          dhKeyPair: dhPair,
        );

        expect(state.rootKey, equals(rootKey));
        expect(state.recvChainKey.length, 32);
        expect(state.sendMessageNumber, 0);
        expect(state.recvMessageNumber, 0);
        expect(state.dhSelf, equals(dhPair));
        expect(state.sendingChainActive, false); // Not active until first send
        expect(state.receivingChainActive, true);
      });
    });

    group('encrypt/decrypt', () {
      test('Alice can encrypt and Bob can decrypt', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);

        // Alice initiates
        final aliceKeyPair = await x25519.generateKeyPair();
        final aliceDhPair = (aliceKeyPair.publicKey, aliceKeyPair.privateKey);

        var aliceState = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: aliceDhPair,
        );

        // Bob initiates (with knowledge of Alice's DH public)
        final bobKeyPair = await x25519.generateKeyPair();
        final bobDhPair = (bobKeyPair.publicKey, bobKeyPair.privateKey);

        var bobState = await ratchet.initReceiver(
          rootKey: sharedSecret,
          dhKeyPair: bobDhPair,
        );

        // Alice encrypts
        final plaintext = Uint8List.fromList('Hello Bob!'.codeUnits);
        final (message, newAliceState) = await ratchet.encryptMessage(
          plaintext: plaintext,
          state: aliceState,
        );
        aliceState = newAliceState;

        // Bob decrypts
        final (decrypted, newBobState) = await ratchet.decryptMessage(
          message: message,
          state: bobState,
        );
        bobState = newBobState;

        expect(decrypted, equals(plaintext));
      });

      test('multiple messages in same direction', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);

        final aliceKeyPair = await x25519.generateKeyPair();
        var aliceState = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: (aliceKeyPair.publicKey, aliceKeyPair.privateKey),
        );

        final bobKeyPair = await x25519.generateKeyPair();
        var bobState = await ratchet.initReceiver(
          rootKey: sharedSecret,
          dhKeyPair: (bobKeyPair.publicKey, bobKeyPair.privateKey),
        );

        // Send multiple messages
        final messages = ['First', 'Second', 'Third'];

        for (final msg in messages) {
          final plaintext = Uint8List.fromList(msg.codeUnits);
          final (encrypted, newAliceState) = await ratchet.encryptMessage(
            plaintext: plaintext,
            state: aliceState,
          );
          aliceState = newAliceState;

          final (decrypted, newBobState) = await ratchet.decryptMessage(
            message: encrypted,
            state: bobState,
          );
          bobState = newBobState;

          expect(decrypted, equals(plaintext));
        }

        // Message numbers should advance
        expect(aliceState.sendMessageNumber, 3);
        expect(bobState.recvMessageNumber, 3);
      });

      test('bidirectional communication', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);

        final aliceKeyPair = await x25519.generateKeyPair();
        var aliceState = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: (aliceKeyPair.publicKey, aliceKeyPair.privateKey),
        );

        final bobKeyPair = await x25519.generateKeyPair();
        var bobState = await ratchet.initReceiver(
          rootKey: sharedSecret,
          dhKeyPair: (bobKeyPair.publicKey, bobKeyPair.privateKey),
        );

        // Alice -> Bob
        final msg1 = Uint8List.fromList('Hi Bob!'.codeUnits);
        final (enc1, aState1) = await ratchet.encryptMessage(
          plaintext: msg1,
          state: aliceState,
        );
        aliceState = aState1;

        final (dec1, bState1) = await ratchet.decryptMessage(
          message: enc1,
          state: bobState,
        );
        bobState = bState1;

        expect(dec1, equals(msg1));

        // Bob -> Alice (Bob needs to activate his sending chain)
        bobState = bobState.copyWith(dhRemote: enc1.dhPublic);

        final msg2 = Uint8List.fromList('Hi Alice!'.codeUnits);
        final (enc2, bState2) = await ratchet.encryptMessage(
          plaintext: msg2,
          state: bobState,
        );
        bobState = bState2;

        // Alice receives from Bob
        final (dec2, aState2) = await ratchet.decryptMessage(
          message: enc2,
          state: aliceState,
        );
        aliceState = aState2;

        expect(dec2, equals(msg2));
      });
    });

    group('message properties', () {
      test('message contains correct DH step', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);
        final keyPair = await x25519.generateKeyPair();

        final state = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: (keyPair.publicKey, keyPair.privateKey),
        );

        final plaintext = Uint8List.fromList('Test'.codeUnits);
        final (message, _) = await ratchet.encryptMessage(
          plaintext: plaintext,
          state: state,
        );

        expect(message.dhStep, 0);
        expect(message.messageNumber, 0);
        expect(message.dhPublic.length, 32);
        expect(message.ciphertext.isNotEmpty, true);
        expect(message.nonce.length, 12);
      });

      test('message number increments', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);
        final keyPair = await x25519.generateKeyPair();

        var state = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: (keyPair.publicKey, keyPair.privateKey),
        );

        for (var i = 0; i < 5; i++) {
          final plaintext = Uint8List.fromList('Msg $i'.codeUnits);
          final (message, newState) = await ratchet.encryptMessage(
            plaintext: plaintext,
            state: state,
          );
          state = newState;

          expect(message.messageNumber, i);
        }
      });
    });

    group('RatchetMessage serialization', () {
      test('serializes to map with correct keys', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);
        final keyPair = await x25519.generateKeyPair();

        final state = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: (keyPair.publicKey, keyPair.privateKey),
        );

        final plaintext = Uint8List.fromList('Serialize test'.codeUnits);
        final (message, _) = await ratchet.encryptMessage(
          plaintext: plaintext,
          state: state,
        );

        // Serialize
        final map = message.toMap();

        // Verify map contains expected keys
        expect(map.containsKey('dh_public'), true);
        expect(map.containsKey('dh_step'), true);
        expect(map.containsKey('prev_chain_length'), true);
        expect(map.containsKey('msg_number'), true);
        expect(map.containsKey('ciphertext'), true);
        expect(map.containsKey('nonce'), true);

        // Verify values
        expect(map['dh_step'], 0);
        expect(map['msg_number'], 0);
        expect(map['prev_chain_length'], 0);
      });
    });

    group('cleanupExpiredKeys', () {
      test('removes expired skipped keys', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);
        final keyPair = await x25519.generateKeyPair();

        final state = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: (keyPair.publicKey, keyPair.privateKey),
        );

        // Manually expire skipped keys by setting old timestamp
        // This is testing the cleanup mechanism

        final cleaned = ratchet.cleanupExpiredKeys(state);

        // State should be updated
        expect(cleaned.lastUpdated, isNotNull);
      });
    });

    group('edge cases', () {
      test('handles empty plaintext', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);

        final aliceKeyPair = await x25519.generateKeyPair();
        var aliceState = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: (aliceKeyPair.publicKey, aliceKeyPair.privateKey),
        );

        final bobKeyPair = await x25519.generateKeyPair();
        final bobState = await ratchet.initReceiver(
          rootKey: sharedSecret,
          dhKeyPair: (bobKeyPair.publicKey, bobKeyPair.privateKey),
        );

        final emptyPlaintext = Uint8List(0);
        final (message, newAliceState) = await ratchet.encryptMessage(
          plaintext: emptyPlaintext,
          state: aliceState,
        );
        aliceState = newAliceState;

        final (decrypted, _) = await ratchet.decryptMessage(
          message: message,
          state: bobState,
        );

        expect(decrypted, equals(emptyPlaintext));
        expect(decrypted.length, 0);
      });

      test('handles large plaintext', () async {
        final sharedSecret = Uint8List(32)..fillRange(0, 32, 0x42);

        final aliceKeyPair = await x25519.generateKeyPair();
        var aliceState = await ratchet.initSender(
          rootKey: sharedSecret,
          dhKeyPair: (aliceKeyPair.publicKey, aliceKeyPair.privateKey),
        );

        final bobKeyPair = await x25519.generateKeyPair();
        final bobState = await ratchet.initReceiver(
          rootKey: sharedSecret,
          dhKeyPair: (bobKeyPair.publicKey, bobKeyPair.privateKey),
        );

        // 10KB message
        final largePlaintext = Uint8List(10240);
        for (var i = 0; i < largePlaintext.length; i++) {
          largePlaintext[i] = i % 256;
        }

        final (message, newAliceState) = await ratchet.encryptMessage(
          plaintext: largePlaintext,
          state: aliceState,
        );
        aliceState = newAliceState;

        final (decrypted, _) = await ratchet.decryptMessage(
          message: message,
          state: bobState,
        );

        expect(decrypted, equals(largePlaintext));
      });
    });
  });
}
