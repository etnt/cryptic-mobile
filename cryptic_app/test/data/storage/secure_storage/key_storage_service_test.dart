// test/data/storage/secure_storage/key_storage_service_test.dart
//
// Tests for KeyStorageService

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:cryptic_app/data/crypto/keys/identity_key_pair.dart';
import 'package:cryptic_app/data/crypto/keys/signed_prekey.dart';
import 'package:cryptic_app/data/crypto/keys/one_time_prekey.dart';
import 'package:cryptic_app/data/crypto/ratchet/ratchet_state.dart';
import 'package:cryptic_app/data/storage/secure_storage/secure_storage_service.dart';
import 'package:cryptic_app/data/storage/secure_storage/key_storage_service.dart';

@GenerateMocks([SecureStorageService])
import 'key_storage_service_test.mocks.dart';

void main() {
  late MockSecureStorageService mockSecureStorage;
  late KeyStorageService keyStorage;

  setUp(() {
    mockSecureStorage = MockSecureStorageService();
    keyStorage = KeyStorageService(secureStorage: mockSecureStorage);
  });

  group('KeyStorageService', () {
    group('Identity Keys', () {
      test('saveIdentityKeyPair stores keys', () async {
        final keyPair = IdentityKeyPair(
          signPublicKey: Uint8List(32)..fillRange(0, 32, 1),
          signPrivateKey: Uint8List(64)..fillRange(0, 64, 2),
          dhPublicKey: Uint8List(32)..fillRange(0, 32, 3),
          dhPrivateKey: Uint8List(32)..fillRange(0, 32, 4),
        );

        when(mockSecureStorage.writeJson(
          key: KeyStorageKeys.identityKeys,
          value: keyPair.toMap(),
        )).thenAnswer((_) async {});

        await keyStorage.saveIdentityKeyPair(keyPair);

        verify(mockSecureStorage.writeJson(
          key: KeyStorageKeys.identityKeys,
          value: keyPair.toMap(),
        )).called(1);
      });

      test('loadIdentityKeyPair returns null when not found', () async {
        when(mockSecureStorage.readJson(key: KeyStorageKeys.identityKeys))
            .thenAnswer((_) async => null);

        final result = await keyStorage.loadIdentityKeyPair();

        expect(result, isNull);
      });

      test('hasIdentityKeys returns true when keys exist', () async {
        when(mockSecureStorage.containsKey(key: KeyStorageKeys.identityKeys))
            .thenAnswer((_) async => true);

        final result = await keyStorage.hasIdentityKeys();

        expect(result, isTrue);
      });

      test('hasIdentityKeys returns false when no keys', () async {
        when(mockSecureStorage.containsKey(key: KeyStorageKeys.identityKeys))
            .thenAnswer((_) async => false);

        final result = await keyStorage.hasIdentityKeys();

        expect(result, isFalse);
      });

      test('deleteIdentityKeyPair removes keys', () async {
        when(mockSecureStorage.delete(key: KeyStorageKeys.identityKeys))
            .thenAnswer((_) async {});

        await keyStorage.deleteIdentityKeyPair();

        verify(mockSecureStorage.delete(key: KeyStorageKeys.identityKeys))
            .called(1);
      });
    });

    group('Signed Prekey', () {
      test('saveSignedPrekey stores prekey', () async {
        final prekey = SignedPrekey(
          keyId: 1,
          publicKey: Uint8List(32)..fillRange(0, 32, 5),
          privateKey: Uint8List(32)..fillRange(0, 32, 6),
          signature: Uint8List(64)..fillRange(0, 64, 7),
          timestamp: DateTime(2024, 1, 1),
        );

        when(mockSecureStorage.writeJson(
          key: KeyStorageKeys.signedPrekey,
          value: prekey.toMap(),
        )).thenAnswer((_) async {});

        await keyStorage.saveSignedPrekey(prekey);

        verify(mockSecureStorage.writeJson(
          key: KeyStorageKeys.signedPrekey,
          value: prekey.toMap(),
        )).called(1);
      });

      test('loadSignedPrekey returns null when not found', () async {
        when(mockSecureStorage.readJson(key: KeyStorageKeys.signedPrekey))
            .thenAnswer((_) async => null);

        final result = await keyStorage.loadSignedPrekey();

        expect(result, isNull);
      });
    });

    group('One-Time Prekeys', () {
      test('saveOneTimePrekeys stores prekeys', () async {
        final prekeys = [
          OneTimePrekey(
            keyId: 1,
            publicKey: Uint8List(32)..fillRange(0, 32, 8),
            privateKey: Uint8List(32)..fillRange(0, 32, 9),
          ),
          OneTimePrekey(
            keyId: 2,
            publicKey: Uint8List(32)..fillRange(0, 32, 10),
            privateKey: Uint8List(32)..fillRange(0, 32, 11),
          ),
        ];

        final expectedJson = jsonEncode(prekeys.map((p) => p.toMap()).toList());

        when(mockSecureStorage.write(
          key: KeyStorageKeys.oneTimePrekeys,
          value: expectedJson,
        )).thenAnswer((_) async {});

        await keyStorage.saveOneTimePrekeys(prekeys);

        verify(mockSecureStorage.write(
          key: KeyStorageKeys.oneTimePrekeys,
          value: expectedJson,
        )).called(1);
      });

      test('loadOneTimePrekeys returns empty list when not found', () async {
        when(mockSecureStorage.read(key: KeyStorageKeys.oneTimePrekeys))
            .thenAnswer((_) async => null);

        final result = await keyStorage.loadOneTimePrekeys();

        expect(result, isEmpty);
      });

      test('loadOneTimePrekeys decodes stored prekeys', () async {
        final prekeys = [
          OneTimePrekey(
            keyId: 1,
            publicKey: Uint8List(32)..fillRange(0, 32, 8),
            privateKey: Uint8List(32)..fillRange(0, 32, 9),
          ),
        ];

        final storedJson = jsonEncode(prekeys.map((p) => p.toMap()).toList());

        when(mockSecureStorage.read(key: KeyStorageKeys.oneTimePrekeys))
            .thenAnswer((_) async => storedJson);

        final result = await keyStorage.loadOneTimePrekeys();

        expect(result, hasLength(1));
        expect(result[0].keyId, 1);
      });
    });

    group('Session State', () {
      test('saveSessionState stores session', () async {
        final state = RatchetState(
          rootKey: Uint8List(32)..fillRange(0, 32, 0x11),
          sendChainKey: Uint8List(32)..fillRange(0, 32, 0x22),
          sendMessageNumber: 0,
          recvChainKey: Uint8List(32)..fillRange(0, 32, 0x33),
          recvMessageNumber: 0,
          prevRecvChainLength: 0,
          dhSelf: (
            Uint8List(32)..fillRange(0, 32, 0x44),
            Uint8List(32)..fillRange(0, 32, 0x55),
          ),
          dhRatchetStep: 0,
          sendingChainActive: true,
          receivingChainActive: true,
          createdAt: DateTime(2024, 1, 1),
        );

        when(mockSecureStorage.writeJson(
          key: KeyStorageKeys.sessionKey('alice'),
          value: state.toMap(),
        )).thenAnswer((_) async {});

        await keyStorage.saveSessionState(
          peerUsername: 'alice',
          state: state,
        );

        verify(mockSecureStorage.writeJson(
          key: KeyStorageKeys.sessionKey('alice'),
          value: state.toMap(),
        )).called(1);
      });

      test('loadSessionState returns null when not found', () async {
        when(mockSecureStorage.readJson(
          key: KeyStorageKeys.sessionKey('bob'),
        )).thenAnswer((_) async => null);

        final result = await keyStorage.loadSessionState(peerUsername: 'bob');

        expect(result, isNull);
      });

      test('hasSession returns correct value', () async {
        when(mockSecureStorage.containsKey(
          key: KeyStorageKeys.sessionKey('alice'),
        )).thenAnswer((_) async => true);

        final result = await keyStorage.hasSession(peerUsername: 'alice');

        expect(result, isTrue);
      });

      test('listSessionPeers extracts peer names', () async {
        when(mockSecureStorage.readAll()).thenAnswer((_) async => {
              'cryptic_session_alice': 'data1',
              'cryptic_session_bob': 'data2',
              'cryptic_other_key': 'data3',
            });

        final result = await keyStorage.listSessionPeers();

        expect(result, containsAll(['alice', 'bob']));
        expect(result, hasLength(2));
      });
    });

    group('User Metadata', () {
      test('saveUsername stores username', () async {
        when(mockSecureStorage.write(
          key: KeyStorageKeys.username,
          value: 'testuser',
        )).thenAnswer((_) async {});

        await keyStorage.saveUsername('testuser');

        verify(mockSecureStorage.write(
          key: KeyStorageKeys.username,
          value: 'testuser',
        )).called(1);
      });

      test('loadUsername returns stored username', () async {
        when(mockSecureStorage.read(key: KeyStorageKeys.username))
            .thenAnswer((_) async => 'testuser');

        final result = await keyStorage.loadUsername();

        expect(result, 'testuser');
      });

      test('saveServerInfo stores host and port', () async {
        when(mockSecureStorage.writeJson(
          key: KeyStorageKeys.serverInfo,
          value: {'host': 'localhost', 'port': 8443},
        )).thenAnswer((_) async {});

        await keyStorage.saveServerInfo(host: 'localhost', port: 8443);

        verify(mockSecureStorage.writeJson(
          key: KeyStorageKeys.serverInfo,
          value: {'host': 'localhost', 'port': 8443},
        )).called(1);
      });

      test('loadServerInfo returns stored info', () async {
        when(mockSecureStorage.readJson(key: KeyStorageKeys.serverInfo))
            .thenAnswer((_) async => {'host': 'localhost', 'port': 8443});

        final result = await keyStorage.loadServerInfo();

        expect(result?.host, 'localhost');
        expect(result?.port, 8443);
      });

      test('loadServerInfo returns null when not found', () async {
        when(mockSecureStorage.readJson(key: KeyStorageKeys.serverInfo))
            .thenAnswer((_) async => null);

        final result = await keyStorage.loadServerInfo();

        expect(result, isNull);
      });
    });

    group('Initialization', () {
      test('isInitialized returns true when identity keys exist', () async {
        when(mockSecureStorage.containsKey(key: KeyStorageKeys.identityKeys))
            .thenAnswer((_) async => true);

        final result = await keyStorage.isInitialized();

        expect(result, isTrue);
      });

      test('isInitialized returns false when no identity keys', () async {
        when(mockSecureStorage.containsKey(key: KeyStorageKeys.identityKeys))
            .thenAnswer((_) async => false);

        final result = await keyStorage.isInitialized();

        expect(result, isFalse);
      });
    });
  });
}
