/// Client-to-server protocol messages for Cryptic WebSocket communication.
///
/// These messages are sent from the Flutter client to the Cryptic server.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'protocol_message.dart';

/// Upload identity keys for initial user setup.
///
/// Sent when a user first registers or needs to re-upload their keys.
class UploadIdentityKeysMessage extends ProtocolMessage {
  /// Creates a new upload identity keys message.
  UploadIdentityKeysMessage({
    required this.username,
    required this.identitySignPublic,
    required this.identityDhPublic,
    required this.signedPrekeyPublic,
    required this.signedPrekeySignature,
    required this.signedPrekeyId,
  });

  /// The username for this identity.
  final String username;

  /// Ed25519 identity signing public key (base64).
  final String identitySignPublic;

  /// X25519 identity DH public key (base64).
  final String identityDhPublic;

  /// X25519 signed prekey public key (base64).
  final String signedPrekeyPublic;

  /// Ed25519 signature of the signed prekey (base64).
  final String signedPrekeySignature;

  /// Unique ID for the signed prekey.
  final int signedPrekeyId;

  @override
  String get type => ClientMessageType.uploadIdentityKeys.value;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'username': username,
        'identity_sign_public': identitySignPublic,
        'identity_dh_public': identityDhPublic,
        'signed_prekey_public': signedPrekeyPublic,
        'signed_prekey_signature': signedPrekeySignature,
        'signed_prekey_id': signedPrekeyId,
      };

  /// Create from identity keys map.
  ///
  /// [keys] should contain:
  /// - identity_sign_key: (publicKey, privateKey) tuple
  /// - identity_dh_key: (publicKey, privateKey) tuple
  /// - signed_prekey: (keyId, publicKey, privateKey) tuple
  /// - signed_prekey_signature: Uint8List signature
  static UploadIdentityKeysMessage fromKeys({
    required String username,
    required Uint8List identitySignPublic,
    required Uint8List identityDhPublic,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPublic,
    required Uint8List signedPrekeySignature,
  }) {
    return UploadIdentityKeysMessage(
      username: username,
      identitySignPublic: base64Encode(identitySignPublic),
      identityDhPublic: base64Encode(identityDhPublic),
      signedPrekeyId: signedPrekeyId,
      signedPrekeyPublic: base64Encode(signedPrekeyPublic),
      signedPrekeySignature: base64Encode(signedPrekeySignature),
    );
  }
}

/// One-time prekey for upload.
class OneTimePrekey {
  /// Creates a one-time prekey.
  OneTimePrekey({
    required this.keyId,
    required this.publicKey,
  });

  /// Unique ID for this prekey (will be base64-encoded for wire format).
  final int keyId;

  /// X25519 public key (base64).
  final String publicKey;

  /// Convert to JSON map.
  ///
  /// The server expects:
  /// - `id`: base64-encoded 8-byte random ID
  /// - `public_key`: base64-encoded X25519 public key
  Map<String, dynamic> toJson() {
    // Convert keyId to 8-byte binary and base64-encode it
    final idBytes = Uint8List(8);
    final view = ByteData.view(idBytes.buffer);
    view.setInt64(0, keyId, Endian.big);
    return {
      'id': base64Encode(idBytes),
      'public_key': publicKey,
    };
  }

  /// Create from raw bytes.
  factory OneTimePrekey.fromBytes({
    required int keyId,
    required Uint8List publicKey,
  }) {
    return OneTimePrekey(
      keyId: keyId,
      publicKey: base64Encode(publicKey),
    );
  }
}

/// Upload one-time prekeys bundle.
///
/// The server consumes one-time prekeys as other users initiate X3DH.
/// Clients should periodically upload new prekeys.
class UploadPrekeyBundleMessage extends ProtocolMessage {
  /// Creates a new upload prekey bundle message.
  UploadPrekeyBundleMessage({
    required this.username,
    required this.oneTimePrekeys,
  });

  /// The username this bundle belongs to.
  final String username;

  /// List of one-time prekeys to upload.
  final List<OneTimePrekey> oneTimePrekeys;

  @override
  String get type => ClientMessageType.uploadPrekeyBundle.value;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'username': username,
        'one_time_prekeys': oneTimePrekeys.map((k) => k.toJson()).toList(),
      };
}

/// Request another user's key bundle for X3DH.
class GetKeyBundleMessage extends ProtocolMessage {
  /// Creates a get key bundle request.
  GetKeyBundleMessage({required this.username});

  /// Username whose key bundle to fetch.
  final String username;

  @override
  String get type => ClientMessageType.getKeyBundle.value;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'username': username,
      };
}

/// Send X3DH initial message to establish a session.
class X3dhMessage extends ProtocolMessage {
  /// Creates an X3DH message.
  X3dhMessage({
    required this.messageId,
    required this.fromUser,
    required this.toUser,
    required this.identityKey,
    required this.ephemeralKey,
    this.usedOneTimePrekeyId,
    required this.ciphertext,
  });

  /// Unique message ID for acknowledgment tracking.
  final String messageId;

  /// Sender username.
  final String fromUser;

  /// Recipient username.
  final String toUser;

  /// Sender's identity DH public key (base64).
  final String identityKey;

  /// Ephemeral X25519 public key for this message (base64).
  final String ephemeralKey;

  /// ID of the one-time prekey used (null if none available).
  final int? usedOneTimePrekeyId;

  /// Encrypted message content (base64).
  final String ciphertext;

  @override
  String get type => ClientMessageType.x3dh.value;

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': type,
      'message_id': messageId,
      'from_user': fromUser,
      'to_user': toUser,
      'identity_key': identityKey,
      'ephemeral_key': ephemeralKey,
      'ciphertext': ciphertext,
    };
    if (usedOneTimePrekeyId != null) {
      json['used_one_time_prekey_id'] = usedOneTimePrekeyId;
    }
    return json;
  }

  /// Create from raw X3DH output.
  factory X3dhMessage.fromBytes({
    required String messageId,
    required String fromUser,
    required String toUser,
    required Uint8List identityKey,
    required Uint8List ephemeralKey,
    int? usedOneTimePrekeyId,
    required Uint8List ciphertext,
  }) {
    return X3dhMessage(
      messageId: messageId,
      fromUser: fromUser,
      toUser: toUser,
      identityKey: base64Encode(identityKey),
      ephemeralKey: base64Encode(ephemeralKey),
      usedOneTimePrekeyId: usedOneTimePrekeyId,
      ciphertext: base64Encode(ciphertext),
    );
  }
}

/// Send a ratchet message in an established session.
class RatchetMessage extends ProtocolMessage {
  /// Creates a ratchet message.
  RatchetMessage({
    required this.messageId,
    required this.fromUser,
    required this.toUser,
    required this.dhPublic,
    required this.previousChainLength,
    required this.messageNumber,
    required this.ciphertext,
  });

  /// Unique message ID for acknowledgment tracking.
  final String messageId;

  /// Sender username.
  final String fromUser;

  /// Recipient username.
  final String toUser;

  /// Current ratchet DH public key (base64).
  final String dhPublic;

  /// Length of previous sending chain.
  final int previousChainLength;

  /// Message number in current chain.
  final int messageNumber;

  /// Encrypted message content (base64).
  final String ciphertext;

  @override
  String get type => ClientMessageType.ratchet.value;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'message_id': messageId,
        'from_user': fromUser,
        'to_user': toUser,
        'dh_public': dhPublic,
        'previous_chain_length': previousChainLength,
        'message_number': messageNumber,
        'ciphertext': ciphertext,
      };

  /// Create from raw ratchet output.
  factory RatchetMessage.fromBytes({
    required String messageId,
    required String fromUser,
    required String toUser,
    required Uint8List dhPublic,
    required int previousChainLength,
    required int messageNumber,
    required Uint8List ciphertext,
  }) {
    return RatchetMessage(
      messageId: messageId,
      fromUser: fromUser,
      toUser: toUser,
      dhPublic: base64Encode(dhPublic),
      previousChainLength: previousChainLength,
      messageNumber: messageNumber,
      ciphertext: base64Encode(ciphertext),
    );
  }
}

/// Request list of registered users (admin only).
class ListUsersMessage extends ProtocolMessage {
  /// Creates a list users request.
  ListUsersMessage();

  @override
  String get type => ClientMessageType.listUsers.value;

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

/// Request list of online users (non-admin).
class OnlineUsersMessage extends ProtocolMessage {
  /// Creates an online users request.
  OnlineUsersMessage();

  @override
  String get type => ClientMessageType.onlineUsers.value;

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

/// High-level send message request.
///
/// This is used by the engine to request encryption and sending.
/// The engine will convert this to either X3DH or Ratchet message.
class SendMessageRequest extends ProtocolMessage {
  /// Creates a send message request.
  SendMessageRequest({
    required this.toUser,
    required this.plaintext,
  });

  /// Recipient username.
  final String toUser;

  /// Plaintext message to send.
  final String plaintext;

  @override
  String get type => ClientMessageType.sendMessage.value;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'to_user': toUser,
        'plaintext': plaintext,
      };
}
