import 'dart:convert';

import 'package:cryptic_app/data/network/protocol/protocol_message.dart';
import 'package:cryptic_app/data/network/protocol/server_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerMessageType', () {
    test('should have correct wire values', () {
      expect(ServerMessageType.welcome.value, 'welcome');
      expect(ServerMessageType.success.value, 'success');
      expect(ServerMessageType.users.value, 'users');
      expect(ServerMessageType.keyBundle.value, 'key_bundle');
      expect(ServerMessageType.message.value, 'message');
      expect(ServerMessageType.messageSent.value, 'message_sent');
      expect(ServerMessageType.error.value, 'error');
      expect(ServerMessageType.userStatus.value, 'user_status');
      expect(ServerMessageType.pendingMessagesDelivered.value,
          'pending_messages_delivered');
    });

    test('should parse from value', () {
      expect(ServerMessageType.fromValue('welcome'), ServerMessageType.welcome);
      expect(ServerMessageType.fromValue('key_bundle'),
          ServerMessageType.keyBundle);
      expect(ServerMessageType.fromValue('unknown'), isNull);
    });
  });

  group('ServerMessage.fromJson', () {
    test('should parse welcome message', () {
      final json = {
        'type': 'welcome',
        'message': 'Connected to Cryptic Server'
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<WelcomeMessage>());
      expect(
          (message! as WelcomeMessage).message, 'Connected to Cryptic Server');
    });

    test('should parse success message', () {
      final json = {
        'type': 'success',
        'operation': 'upload_identity_keys',
        'message': 'Keys uploaded successfully',
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<SuccessMessage>());
      final success = message! as SuccessMessage;
      expect(success.operation, 'upload_identity_keys');
      expect(success.message, 'Keys uploaded successfully');
    });

    test('should parse users message', () {
      final json = {
        'type': 'users',
        'users': ['alice', 'bob', 'charlie'],
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<UsersMessage>());
      final users = message! as UsersMessage;
      expect(users.users, ['alice', 'bob', 'charlie']);
    });

    test('should parse key bundle message', () {
      final json = {
        'type': 'key_bundle',
        'username': 'bob',
        'identity_sign_key': base64Encode(utf8.encode('sign_key')),
        'identity_dh_key': base64Encode(utf8.encode('dh_key')),
        'signed_prekey': {
          'key_id': 1,
          'public_key': base64Encode(utf8.encode('prekey')),
          'signature': base64Encode(utf8.encode('signature')),
        },
        'one_time_prekey': {
          'key_id': 5,
          'public_key': base64Encode(utf8.encode('otpk')),
        },
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<KeyBundleMessage>());
      final bundle = message! as KeyBundleMessage;
      expect(bundle.username, 'bob');
      expect(bundle.signedPrekey.keyId, 1);
      expect(bundle.oneTimePrekey?.keyId, 5);
    });

    test('should parse key bundle without one-time prekey', () {
      final json = {
        'type': 'key_bundle',
        'username': 'bob',
        'identity_sign_key': 'sign',
        'identity_dh_key': 'dh',
        'signed_prekey': {
          'key_id': 1,
          'public_key': 'pk',
          'signature': 'sig',
        },
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<KeyBundleMessage>());
      final bundle = message! as KeyBundleMessage;
      expect(bundle.oneTimePrekey, isNull);
    });

    test('should parse message sent acknowledgment', () {
      final json = {
        'type': 'message_sent',
        'message_id': 'uuid-123',
        'to_user': 'bob',
        'timestamp': 1699999999,
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<MessageSentMessage>());
      final sent = message! as MessageSentMessage;
      expect(sent.messageId, 'uuid-123');
      expect(sent.toUser, 'bob');
      expect(sent.timestamp, 1699999999);
    });

    test('should parse error message', () {
      final json = {
        'type': 'error',
        'message': 'User not found',
        'success': false,
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<ErrorMessage>());
      final error = message! as ErrorMessage;
      expect(error.message, 'User not found');
      expect(error.success, false);
    });

    test('should parse user status message', () {
      final json = {
        'type': 'user_status',
        'username': 'alice',
        'online': true,
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<UserStatusMessage>());
      final status = message! as UserStatusMessage;
      expect(status.username, 'alice');
      expect(status.isOnline, true);
    });

    test('should parse pending messages delivered', () {
      final json = {
        'type': 'pending_messages_delivered',
        'count': 5,
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<PendingMessagesDeliveredMessage>());
      expect((message! as PendingMessagesDeliveredMessage).count, 5);
    });

    test('should return UnknownServerMessage for unknown type', () {
      final json = {'type': 'future_feature', 'data': 'value'};

      final message = ServerMessage.fromJson(json);

      expect(message, isA<UnknownServerMessage>());
      final unknown = message! as UnknownServerMessage;
      expect(unknown.typeString, 'future_feature');
      expect(unknown.rawJson['data'], 'value');
    });

    test('should return null for missing type', () {
      final json = {'data': 'value'};

      final message = ServerMessage.fromJson(json);

      expect(message, isNull);
    });
  });

  group('ServerMessage.fromJsonString', () {
    test('should parse valid JSON string', () {
      const jsonString = '{"type":"welcome","message":"Hello"}';

      final message = ServerMessage.fromJsonString(jsonString);

      expect(message, isA<WelcomeMessage>());
    });

    test('should return null for invalid JSON', () {
      const jsonString = 'not valid json';

      final message = ServerMessage.fromJsonString(jsonString);

      expect(message, isNull);
    });

    test('should return null for non-object JSON', () {
      const jsonString = '["array", "value"]';

      final message = ServerMessage.fromJsonString(jsonString);

      expect(message, isNull);
    });
  });

  group('IncomingMessage', () {
    test('should parse X3DH message', () {
      final json = {
        'type': 'message',
        'message_type': 'x3dh',
        'from_user': 'alice',
        'to_user': 'bob',
        'identity_key': base64Encode(utf8.encode('ik')),
        'ephemeral_key': base64Encode(utf8.encode('ek')),
        'used_one_time_prekey_id': 3,
        'ciphertext': base64Encode(utf8.encode('ct')),
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<IncomingMessage>());
      final incoming = message! as IncomingMessage;
      expect(incoming.isX3dh, true);
      expect(incoming.isRatchet, false);
      expect(incoming.fromUser, 'alice');
      expect(incoming.toUser, 'bob');
    });

    test('should parse ratchet message', () {
      final json = {
        'type': 'message',
        'message_type': 'ratchet',
        'from_user': 'bob',
        'to_user': 'alice',
        'dh_public': base64Encode(utf8.encode('dh')),
        'previous_chain_length': 5,
        'message_number': 3,
        'ciphertext': base64Encode(utf8.encode('ct')),
      };

      final message = ServerMessage.fromJson(json);

      expect(message, isA<IncomingMessage>());
      final incoming = message! as IncomingMessage;
      expect(incoming.isX3dh, false);
      expect(incoming.isRatchet, true);
    });
  });

  group('IncomingX3dhMessage', () {
    test('should parse from raw data', () {
      final data = {
        'from_user': 'alice',
        'to_user': 'bob',
        'identity_key': base64Encode(utf8.encode('identity')),
        'ephemeral_key': base64Encode(utf8.encode('ephemeral')),
        'used_one_time_prekey_id': 7,
        'ciphertext': base64Encode(utf8.encode('cipher')),
      };

      final x3dh = IncomingX3dhMessage.fromRawData(data);

      expect(x3dh.fromUser, 'alice');
      expect(x3dh.toUser, 'bob');
      expect(x3dh.usedOneTimePrekeyId, 7);
      expect(x3dh.identityKeyBytes, utf8.encode('identity'));
      expect(x3dh.ephemeralKeyBytes, utf8.encode('ephemeral'));
      expect(x3dh.ciphertextBytes, utf8.encode('cipher'));
    });

    test('should handle null one-time prekey id', () {
      final data = {
        'from_user': 'alice',
        'to_user': 'bob',
        'identity_key': base64Encode([1, 2, 3]),
        'ephemeral_key': base64Encode([4, 5, 6]),
        'ciphertext': base64Encode([7, 8, 9]),
      };

      final x3dh = IncomingX3dhMessage.fromRawData(data);

      expect(x3dh.usedOneTimePrekeyId, isNull);
    });
  });

  group('IncomingRatchetMessage', () {
    test('should parse from raw data', () {
      final data = {
        'from_user': 'bob',
        'to_user': 'alice',
        'dh_public': base64Encode(utf8.encode('dh_key')),
        'previous_chain_length': 10,
        'message_number': 5,
        'ciphertext': base64Encode(utf8.encode('encrypted')),
      };

      final ratchet = IncomingRatchetMessage.fromRawData(data);

      expect(ratchet.fromUser, 'bob');
      expect(ratchet.toUser, 'alice');
      expect(ratchet.previousChainLength, 10);
      expect(ratchet.messageNumber, 5);
      expect(ratchet.dhPublicBytes, utf8.encode('dh_key'));
      expect(ratchet.ciphertextBytes, utf8.encode('encrypted'));
    });
  });

  group('MessageSentMessage', () {
    test('should convert timestamp to DateTime', () {
      final message = MessageSentMessage(
        messageId: 'msg-1',
        toUser: 'bob',
        timestamp: 1700000000,
      );

      final dateTime = message.dateTime;

      expect(dateTime.year, 2023);
      expect(dateTime.month, 11);
    });
  });

  group('KeyBundleMessage', () {
    test('should decode base64 keys', () {
      final signKey = utf8.encode('signing_key');
      final dhKey = utf8.encode('dh_key');

      final json = {
        'type': 'key_bundle',
        'username': 'bob',
        'identity_sign_key': base64Encode(signKey),
        'identity_dh_key': base64Encode(dhKey),
        'signed_prekey': {
          'key_id': 1,
          'public_key': 'pk',
          'signature': 'sig',
        },
      };

      final message = ServerMessage.fromJson(json)! as KeyBundleMessage;

      expect(message.identitySignKeyBytes, signKey);
      expect(message.identityDhKeyBytes, dhKey);
    });
  });

  group('SignedPrekey', () {
    test('should decode base64 values', () {
      final pk = utf8.encode('public_key');
      final sig = utf8.encode('signature');

      final prekey = SignedPrekey.fromJson({
        'key_id': 42,
        'public_key': base64Encode(pk),
        'signature': base64Encode(sig),
      });

      expect(prekey.keyId, 42);
      expect(prekey.publicKeyBytes, pk);
      expect(prekey.signatureBytes, sig);
    });
  });

  group('UserStatusMessage', () {
    test('should parse online status from status field', () {
      final json = {
        'type': 'user_status',
        'username': 'alice',
        'status': 'online',
      };

      final message = ServerMessage.fromJson(json)! as UserStatusMessage;

      expect(message.isOnline, true);
    });

    test('should parse offline status', () {
      final json = {
        'type': 'user_status',
        'username': 'alice',
        'status': 'offline',
      };

      final message = ServerMessage.fromJson(json)! as UserStatusMessage;

      expect(message.isOnline, false);
    });
  });
}
