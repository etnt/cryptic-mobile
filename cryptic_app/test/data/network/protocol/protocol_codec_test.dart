import 'package:cryptic_app/data/network/protocol/client_messages.dart';
import 'package:cryptic_app/data/network/protocol/protocol_codec.dart';
import 'package:cryptic_app/data/network/protocol/protocol_message.dart';
import 'package:cryptic_app/data/network/protocol/server_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProtocolCodec', () {
    group('encode', () {
      test('should encode client message to JSON string', () {
        final message = ListUsersMessage();

        final json = ProtocolCodec.encode(message);

        expect(json, '{"type":"list_users"}');
      });

      test('should encode complex message', () {
        final message = X3dhMessage(
          messageId: 'id',
          fromUser: 'alice',
          toUser: 'bob',
          identityKey: 'ik',
          ephemeralKey: 'ek',
          usedOneTimePrekeyId: 1,
          ciphertext: 'ct',
        );

        final json = ProtocolCodec.encode(message);

        expect(json, contains('"type":"x3dh"'));
        expect(json, contains('"message_id":"id"'));
        expect(json, contains('"from_user":"alice"'));
      });
    });

    group('decode', () {
      test('should decode server message from JSON string', () {
        const json = '{"type":"welcome","message":"Hello"}';

        final message = ProtocolCodec.decode(json);

        expect(message, isA<WelcomeMessage>());
        expect((message as WelcomeMessage).message, 'Hello');
      });

      test('should return null for invalid JSON', () {
        const json = 'not json';

        final message = ProtocolCodec.decode(json);

        expect(message, isNull);
      });

      test('should return null for missing type', () {
        const json = '{"data":"value"}';

        final message = ProtocolCodec.decode(json);

        expect(message, isNull);
      });
    });

    group('decodeMap', () {
      test('should decode from map', () {
        final map = {'type': 'users', 'users': ['alice', 'bob']};

        final message = ProtocolCodec.decodeMap(map);

        expect(message, isA<UsersMessage>());
        expect((message as UsersMessage).users, ['alice', 'bob']);
      });
    });

    group('parseJson', () {
      test('should parse valid JSON', () {
        const json = '{"key":"value","number":42}';

        final map = ProtocolCodec.parseJson(json);

        expect(map, {'key': 'value', 'number': 42});
      });

      test('should return null for invalid JSON', () {
        const json = '{invalid}';

        final map = ProtocolCodec.parseJson(json);

        expect(map, isNull);
      });

      test('should return null for non-object JSON', () {
        const json = '"just a string"';

        final map = ProtocolCodec.parseJson(json);

        expect(map, isNull);
      });
    });

    group('isKnownServerType', () {
      test('should return true for known types', () {
        expect(ProtocolCodec.isKnownServerType('welcome'), true);
        expect(ProtocolCodec.isKnownServerType('error'), true);
        expect(ProtocolCodec.isKnownServerType('key_bundle'), true);
      });

      test('should return false for unknown types', () {
        expect(ProtocolCodec.isKnownServerType('future_type'), false);
        expect(ProtocolCodec.isKnownServerType(''), false);
      });
    });

    group('isKnownClientType', () {
      test('should return true for known types', () {
        expect(ProtocolCodec.isKnownClientType('x3dh'), true);
        expect(ProtocolCodec.isKnownClientType('ratchet'), true);
        expect(ProtocolCodec.isKnownClientType('list_users'), true);
      });

      test('should return false for unknown types', () {
        expect(ProtocolCodec.isKnownClientType('welcome'), false);
        expect(ProtocolCodec.isKnownClientType(''), false);
      });
    });
  });

  group('IncomingMessageExtension', () {
    test('asX3dh should return parsed X3DH message', () {
      final incoming = IncomingMessage(
        messageType: EncryptedMessageType.x3dh,
        fromUser: 'alice',
        toUser: 'bob',
        rawData: {
          'type': 'message',
          'message_type': 'x3dh',
          'from_user': 'alice',
          'to_user': 'bob',
          'identity_key': 'aWs=', // 'ik' in base64
          'ephemeral_key': 'ZWs=', // 'ek' in base64
          'ciphertext': 'Y3Q=', // 'ct' in base64
        },
      );

      final x3dh = incoming.asX3dh();

      expect(x3dh, isNotNull);
      expect(x3dh!.fromUser, 'alice');
      expect(x3dh.toUser, 'bob');
    });

    test('asX3dh should return null for ratchet message', () {
      final incoming = IncomingMessage(
        messageType: EncryptedMessageType.ratchet,
        fromUser: 'alice',
        toUser: 'bob',
        rawData: {},
      );

      final x3dh = incoming.asX3dh();

      expect(x3dh, isNull);
    });

    test('asRatchet should return parsed ratchet message', () {
      final incoming = IncomingMessage(
        messageType: EncryptedMessageType.ratchet,
        fromUser: 'bob',
        toUser: 'alice',
        rawData: {
          'type': 'message',
          'message_type': 'ratchet',
          'from_user': 'bob',
          'to_user': 'alice',
          'dh_public': 'ZGg=', // 'dh' in base64
          'previous_chain_length': 5,
          'message_number': 3,
          'ciphertext': 'Y3Q=', // 'ct' in base64
        },
      );

      final ratchet = incoming.asRatchet();

      expect(ratchet, isNotNull);
      expect(ratchet!.fromUser, 'bob');
      expect(ratchet.previousChainLength, 5);
      expect(ratchet.messageNumber, 3);
    });

    test('asRatchet should return null for X3DH message', () {
      final incoming = IncomingMessage(
        messageType: EncryptedMessageType.x3dh,
        fromUser: 'alice',
        toUser: 'bob',
        rawData: {},
      );

      final ratchet = incoming.asRatchet();

      expect(ratchet, isNull);
    });
  });
}
