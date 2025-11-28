import 'dart:convert';

import 'package:cryptic_app/data/network/protocol/protocol_message.dart';
import 'package:cryptic_app/data/network/protocol/client_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientMessageType', () {
    test('should have correct wire values', () {
      expect(ClientMessageType.uploadIdentityKeys.value, 'upload_identity_keys');
      expect(ClientMessageType.uploadPrekeyBundle.value, 'upload_prekey_bundle');
      expect(ClientMessageType.getKeyBundle.value, 'get_key_bundle');
      expect(ClientMessageType.x3dh.value, 'x3dh');
      expect(ClientMessageType.ratchet.value, 'ratchet');
      expect(ClientMessageType.listUsers.value, 'list_users');
      expect(ClientMessageType.sendMessage.value, 'send_message');
    });

    test('should parse from value', () {
      expect(ClientMessageType.fromValue('upload_identity_keys'),
          ClientMessageType.uploadIdentityKeys);
      expect(ClientMessageType.fromValue('x3dh'), ClientMessageType.x3dh);
      expect(ClientMessageType.fromValue('unknown'), isNull);
    });
  });

  group('UploadIdentityKeysMessage', () {
    test('should serialize to JSON correctly', () {
      final message = UploadIdentityKeysMessage(
        username: 'alice',
        identitySignPublic: 'sign_key_base64',
        identityDhPublic: 'dh_key_base64',
        signedPrekeyPublic: 'prekey_base64',
        signedPrekeySignature: 'signature_base64',
        signedPrekeyId: 1,
      );

      final json = message.toJson();

      expect(json['type'], 'upload_identity_keys');
      expect(json['username'], 'alice');
      expect(json['identity_sign_public'], 'sign_key_base64');
      expect(json['identity_dh_public'], 'dh_key_base64');
      expect(json['signed_prekey_public'], 'prekey_base64');
      expect(json['signed_prekey_signature'], 'signature_base64');
      expect(json['signed_prekey_id'], 1);
    });

    test('should create from bytes', () {
      final message = UploadIdentityKeysMessage.fromKeys(
        username: 'bob',
        identitySignPublic: utf8.encode('sign_key'),
        identityDhPublic: utf8.encode('dh_key'),
        signedPrekeyId: 5,
        signedPrekeyPublic: utf8.encode('prekey'),
        signedPrekeySignature: utf8.encode('sig'),
      );

      expect(message.username, 'bob');
      expect(message.signedPrekeyId, 5);
      // Verify base64 encoding
      expect(base64Decode(message.identitySignPublic), utf8.encode('sign_key'));
    });

    test('should serialize to valid JSON string', () {
      final message = UploadIdentityKeysMessage(
        username: 'test',
        identitySignPublic: 'a',
        identityDhPublic: 'b',
        signedPrekeyPublic: 'c',
        signedPrekeySignature: 'd',
        signedPrekeyId: 1,
      );

      final jsonString = message.toJsonString();
      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(parsed['type'], 'upload_identity_keys');
      expect(parsed['username'], 'test');
    });
  });

  group('UploadPrekeyBundleMessage', () {
    test('should serialize with prekeys list', () {
      final message = UploadPrekeyBundleMessage(
        username: 'alice',
        oneTimePrekeys: [
          OneTimePrekey(keyId: 1, publicKey: 'key1'),
          OneTimePrekey(keyId: 2, publicKey: 'key2'),
          OneTimePrekey(keyId: 3, publicKey: 'key3'),
        ],
      );

      final json = message.toJson();

      expect(json['type'], 'upload_prekey_bundle');
      expect(json['username'], 'alice');
      expect(json['one_time_prekeys'], hasLength(3));
      expect(json['one_time_prekeys'][0]['key_id'], 1);
      expect(json['one_time_prekeys'][0]['public_key'], 'key1');
    });
  });

  group('GetKeyBundleMessage', () {
    test('should serialize correctly', () {
      final message = GetKeyBundleMessage(username: 'bob');

      final json = message.toJson();

      expect(json['type'], 'get_key_bundle');
      expect(json['username'], 'bob');
    });
  });

  group('X3dhMessage', () {
    test('should serialize with all fields', () {
      final message = X3dhMessage(
        messageId: 'uuid-123',
        fromUser: 'alice',
        toUser: 'bob',
        identityKey: 'identity_base64',
        ephemeralKey: 'ephemeral_base64',
        usedOneTimePrekeyId: 5,
        ciphertext: 'encrypted_data',
      );

      final json = message.toJson();

      expect(json['type'], 'x3dh');
      expect(json['message_id'], 'uuid-123');
      expect(json['from_user'], 'alice');
      expect(json['to_user'], 'bob');
      expect(json['identity_key'], 'identity_base64');
      expect(json['ephemeral_key'], 'ephemeral_base64');
      expect(json['used_one_time_prekey_id'], 5);
      expect(json['ciphertext'], 'encrypted_data');
    });

    test('should omit null one-time prekey id', () {
      final message = X3dhMessage(
        messageId: 'uuid-456',
        fromUser: 'alice',
        toUser: 'bob',
        identityKey: 'identity',
        ephemeralKey: 'ephemeral',
        usedOneTimePrekeyId: null,
        ciphertext: 'data',
      );

      final json = message.toJson();

      expect(json.containsKey('used_one_time_prekey_id'), isFalse);
    });

    test('should create from bytes', () {
      final message = X3dhMessage.fromBytes(
        messageId: 'msg-1',
        fromUser: 'alice',
        toUser: 'bob',
        identityKey: utf8.encode('identity'),
        ephemeralKey: utf8.encode('ephemeral'),
        usedOneTimePrekeyId: 3,
        ciphertext: utf8.encode('cipher'),
      );

      expect(message.fromUser, 'alice');
      expect(message.usedOneTimePrekeyId, 3);
      expect(base64Decode(message.identityKey), utf8.encode('identity'));
    });
  });

  group('RatchetMessage', () {
    test('should serialize correctly', () {
      final message = RatchetMessage(
        messageId: 'msg-789',
        fromUser: 'alice',
        toUser: 'bob',
        dhPublic: 'dh_key_base64',
        previousChainLength: 5,
        messageNumber: 3,
        ciphertext: 'encrypted',
      );

      final json = message.toJson();

      expect(json['type'], 'ratchet');
      expect(json['message_id'], 'msg-789');
      expect(json['from_user'], 'alice');
      expect(json['to_user'], 'bob');
      expect(json['dh_public'], 'dh_key_base64');
      expect(json['previous_chain_length'], 5);
      expect(json['message_number'], 3);
      expect(json['ciphertext'], 'encrypted');
    });

    test('should create from bytes', () {
      final message = RatchetMessage.fromBytes(
        messageId: 'msg-1',
        fromUser: 'alice',
        toUser: 'bob',
        dhPublic: utf8.encode('dh_key'),
        previousChainLength: 10,
        messageNumber: 7,
        ciphertext: utf8.encode('cipher'),
      );

      expect(message.previousChainLength, 10);
      expect(message.messageNumber, 7);
      expect(base64Decode(message.dhPublic), utf8.encode('dh_key'));
    });
  });

  group('ListUsersMessage', () {
    test('should serialize correctly', () {
      final message = ListUsersMessage();

      final json = message.toJson();

      expect(json['type'], 'list_users');
      expect(json.length, 1);
    });
  });

  group('SendMessageRequest', () {
    test('should serialize correctly', () {
      final message = SendMessageRequest(
        toUser: 'bob',
        plaintext: 'Hello, Bob!',
      );

      final json = message.toJson();

      expect(json['type'], 'send_message');
      expect(json['to_user'], 'bob');
      expect(json['plaintext'], 'Hello, Bob!');
    });
  });
}
