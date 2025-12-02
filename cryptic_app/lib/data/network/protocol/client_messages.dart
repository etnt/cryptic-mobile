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
        'user': username,  // Server expects 'user', not 'username'
      };
}

/// Send X3DH initial message to establish a session.
///
/// Server expects these fields:
/// - `from` - sender username
/// - `to` - recipient username
/// - `message_id` - base64 encoded message ID
/// - `ephemeral_public` - base64 encoded ephemeral public key
/// - `otpk_id` - base64 encoded one-time prekey ID (or null)
/// - `ciphertext` - base64 encoded encrypted content
/// - `nonce` - base64 encoded encryption nonce
/// - `signature` - base64 encoded Ed25519 signature over metadata
/// - `metadata` - base64 encoded serialized metadata JSON
class X3dhMessage extends ProtocolMessage {
  /// Creates an X3DH message.
  X3dhMessage({
    required this.messageId,
    required this.fromUser,
    required this.toUser,
    required this.ephemeralPublic,
    this.otpkId,
    required this.ciphertext,
    required this.nonce,
    required this.signature,
    required this.metadata,
  });

  /// Unique message ID for acknowledgment tracking (base64).
  final String messageId;

  /// Sender username.
  final String fromUser;

  /// Recipient username.
  final String toUser;

  /// Ephemeral X25519 public key for this message (base64).
  final String ephemeralPublic;

  /// ID of the one-time prekey used (base64, null if none available).
  final String? otpkId;

  /// Encrypted message content (base64).
  final String ciphertext;

  /// Encryption nonce (base64).
  final String nonce;

  /// Ed25519 signature over the metadata (base64).
  final String signature;

  /// Serialized metadata JSON (base64).
  final String metadata;

  @override
  String get type => ClientMessageType.x3dh.value;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'message_id': messageId,
      'from': fromUser,
      'to': toUser,
      'ephemeral_public': ephemeralPublic,
      'otpk_id': otpkId,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'signature': signature,
      'metadata': metadata,
    };
  }

  /// Create from X3DH message blob output.
  factory X3dhMessage.fromMessageBlob({
    required String messageId,
    required String fromUser,
    required String toUser,
    required Uint8List ephemeralPublic,
    Uint8List? otpkId,
    required Uint8List ciphertext,
    required Uint8List nonce,
    required Uint8List signature,
    required String metadataJson,
  }) {
    return X3dhMessage(
      messageId: messageId,
      fromUser: fromUser,
      toUser: toUser,
      ephemeralPublic: base64Encode(ephemeralPublic),
      otpkId: otpkId != null ? base64Encode(otpkId) : null,
      ciphertext: base64Encode(ciphertext),
      nonce: base64Encode(nonce),
      signature: base64Encode(signature),
      metadata: base64Encode(utf8.encode(metadataJson)),
    );
  }
}

/// Send a ratchet message in an established session.
///
/// Server expects these fields (from cryptic_messages.erl):
/// - `from` - sender username
/// - `to` - recipient username
/// - `message_id` - base64 message ID
/// - `dh_public` - base64 DH public key
/// - `dh_step` - DH ratchet step number
/// - `prev_chain_length` - length of previous chain
/// - `msg_number` - message number in current chain
/// - `ciphertext` - base64 encrypted data
/// - `nonce` - base64 encryption nonce
class RatchetMessage extends ProtocolMessage {
  /// Creates a ratchet message.
  RatchetMessage({
    required this.messageId,
    required this.fromUser,
    required this.toUser,
    required this.dhPublic,
    required this.dhStep,
    required this.prevChainLength,
    required this.msgNumber,
    required this.ciphertext,
    required this.nonce,
  });

  /// Unique message ID for acknowledgment tracking (base64).
  final String messageId;

  /// Sender username.
  final String fromUser;

  /// Recipient username.
  final String toUser;

  /// Current ratchet DH public key (base64).
  final String dhPublic;

  /// DH ratchet step number.
  final int dhStep;

  /// Length of previous receiving chain.
  final int prevChainLength;

  /// Message number in current sending chain.
  final int msgNumber;

  /// Encrypted message content (base64).
  final String ciphertext;

  /// Encryption nonce (base64).
  final String nonce;

  @override
  String get type => ClientMessageType.ratchet.value;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'message_id': messageId,
        'from': fromUser,
        'to': toUser,
        'dh_public': dhPublic,
        'dh_step': dhStep,
        'prev_chain_length': prevChainLength,
        'msg_number': msgNumber,
        'ciphertext': ciphertext,
        'nonce': nonce,
      };

  /// Create from crypto layer RatchetMessage.
  factory RatchetMessage.fromCryptoMessage({
    required String messageId,
    required String fromUser,
    required String toUser,
    required Uint8List dhPublic,
    required int dhStep,
    required int prevChainLength,
    required int msgNumber,
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    return RatchetMessage(
      messageId: messageId,
      fromUser: fromUser,
      toUser: toUser,
      dhPublic: base64Encode(dhPublic),
      dhStep: dhStep,
      prevChainLength: prevChainLength,
      msgNumber: msgNumber,
      ciphertext: base64Encode(ciphertext),
      nonce: base64Encode(nonce),
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
