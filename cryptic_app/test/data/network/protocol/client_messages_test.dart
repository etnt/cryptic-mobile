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
      expect(ClientMessageType.onlineUsers.value, 'online_users');
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
      // Server expects 'id' as base64-encoded 8-byte integer
      expect(json['one_time_prekeys'][0]['id'], isA<String>());
      expect(json['one_time_prekeys'][0]['public_key'], 'key1');
    });
  });

  group('GetKeyBundleMessage', () {
    test('should serialize correctly', () {
      final message = GetKeyBundleMessage(username: 'bob');

      final json = message.toJson();

      expect(json['type'], 'get_key_bundle');
      expect(json['user'], 'bob');  // Server expects 'user', not 'username'
    });
  });

  group('X3dhMessage', () {
    test('should serialize with all fields', () {
      final message = X3dhMessage(
        messageId: 'uuid-123',
        fromUser: 'alice',
        toUser: 'bob',
        ephemeralPublic: 'ephemeral_base64',
        otpkId: 'otpk_id_base64',
        ciphertext: 'encrypted_data',
        nonce: 'nonce_base64',
        signature: 'signature_base64',
        metadata: 'metadata_base64',
      );

      final json = message.toJson();

      expect(json['type'], 'x3dh');
      expect(json['message_id'], 'uuid-123');
      expect(json['from'], 'alice');
      expect(json['to'], 'bob');
      expect(json['ephemeral_public'], 'ephemeral_base64');
      expect(json['otpk_id'], 'otpk_id_base64');
      expect(json['ciphertext'], 'encrypted_data');
      expect(json['nonce'], 'nonce_base64');
      expect(json['signature'], 'signature_base64');
      expect(json['metadata'], 'metadata_base64');
    });

    test('should include null otpk_id when not provided', () {
      final message = X3dhMessage(
        messageId: 'uuid-456',
        fromUser: 'alice',
        toUser: 'bob',
        ephemeralPublic: 'ephemeral',
        otpkId: null,
        ciphertext: 'data',
        nonce: 'nonce',
        signature: 'sig',
        metadata: 'meta',
      );

      final json = message.toJson();

      expect(json['otpk_id'], isNull);
    });

    test('should create from message blob data', () {
      final message = X3dhMessage.fromMessageBlob(
        messageId: 'msg-1',
        fromUser: 'alice',
        toUser: 'bob',
        ephemeralPublic: utf8.encode('ephemeral'),
        otpkId: utf8.encode('otpk123'),
        ciphertext: utf8.encode('cipher'),
        nonce: utf8.encode('nonce'),
        signature: utf8.encode('signature'),
        metadataJson: '{"version":1}',
      );

      expect(message.fromUser, 'alice');
      expect(message.otpkId, isNotNull);
      expect(base64Decode(message.ephemeralPublic), utf8.encode('ephemeral'));
      // metadata should be base64 of the JSON string
      expect(utf8.decode(base64Decode(message.metadata)), '{"version":1}');
    });
  });

  group('RatchetMessage', () {
    test('should serialize correctly', () {
      final message = RatchetMessage(
        messageId: 'msg-789',
        fromUser: 'alice',
        toUser: 'bob',
        dhPublic: 'dh_key_base64',
        dhStep: 2,
        prevChainLength: 5,
        msgNumber: 3,
        ciphertext: 'encrypted',
        nonce: 'nonce_base64',
      );

      final json = message.toJson();

      expect(json['type'], 'ratchet');
      expect(json['message_id'], 'msg-789');
      expect(json['from'], 'alice');
      expect(json['to'], 'bob');
      expect(json['dh_public'], 'dh_key_base64');
      expect(json['dh_step'], 2);
      expect(json['prev_chain_length'], 5);
      expect(json['msg_number'], 3);
      expect(json['ciphertext'], 'encrypted');
      expect(json['nonce'], 'nonce_base64');
    });

    test('should create from crypto message', () {
      final message = RatchetMessage.fromCryptoMessage(
        messageId: 'msg-1',
        fromUser: 'alice',
        toUser: 'bob',
        dhPublic: utf8.encode('dh_key'),
        dhStep: 1,
        prevChainLength: 0,
        msgNumber: 0,
        ciphertext: utf8.encode('cipher'),
        nonce: utf8.encode('nonce'),
      );

      expect(message.fromUser, 'alice');
      expect(message.dhStep, 1);
      expect(base64Decode(message.dhPublic), utf8.encode('dh_key'));
      expect(base64Decode(message.nonce), utf8.encode('nonce'));
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

  group('OnlineUsersMessage', () {
    test('should serialize correctly', () {
      final message = OnlineUsersMessage();

      final json = message.toJson();

      expect(json['type'], 'online_users');
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
