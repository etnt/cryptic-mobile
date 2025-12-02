/// Server-to-client protocol messages for Cryptic WebSocket communication.
///
/// These messages are received from the Cryptic server.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'protocol_message.dart';

/// Base class for server messages.
abstract class ServerMessage {
  /// The message type.
  ServerMessageType get type;

  /// Parse a server message from JSON.
  static ServerMessage? fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    if (typeStr == null) return null;

    final type = ServerMessageType.fromValue(typeStr);
    if (type == null) {
      // Unknown message type - return as unknown
      return UnknownServerMessage(typeStr, json);
    }

    return switch (type) {
      ServerMessageType.welcome => WelcomeMessage.fromJson(json),
      ServerMessageType.success => SuccessMessage.fromJson(json),
      ServerMessageType.users => UsersMessage.fromJson(json),
      ServerMessageType.onlineUsers => OnlineUsersResponseMessage.fromJson(json),
      ServerMessageType.keyBundle => KeyBundleMessage.fromJson(json),
      ServerMessageType.message => IncomingMessage.fromJson(json),
      ServerMessageType.messageSent => MessageSentMessage.fromJson(json),
      ServerMessageType.error => ErrorMessage.fromJson(json),
      ServerMessageType.userStatus => UserStatusMessage.fromJson(json),
      ServerMessageType.pendingMessagesDelivered =>
        PendingMessagesDeliveredMessage.fromJson(json),
    };
  }

  /// Parse from JSON string.
  static ServerMessage? fromJsonString(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return fromJson(json);
    } catch (e, stack) {
      print('[ServerMessage] Error parsing JSON: $e');
      print('[ServerMessage] Stack: $stack');
      print('[ServerMessage] Raw JSON: ${jsonString.substring(0, jsonString.length > 200 ? 200 : jsonString.length)}...');
      return null;
    }
  }
}

/// Unknown server message type (for forward compatibility).
class UnknownServerMessage extends ServerMessage {
  /// Creates an unknown server message.
  UnknownServerMessage(this.typeString, this.rawJson);

  /// The type string from the message.
  final String typeString;

  /// The raw JSON data.
  final Map<String, dynamic> rawJson;

  @override
  ServerMessageType get type =>
      throw UnsupportedError('Unknown message type: $typeString');
}

/// Welcome message received on connection.
class WelcomeMessage extends ServerMessage {
  /// Creates a welcome message.
  WelcomeMessage({required this.message});

  /// Welcome message content.
  final String message;

  @override
  ServerMessageType get type => ServerMessageType.welcome;

  /// Parse from JSON.
  factory WelcomeMessage.fromJson(Map<String, dynamic> json) {
    return WelcomeMessage(
      message: json['message'] as String? ?? 'Connected to Cryptic Server',
    );
  }
}

/// Success response for operations.
class SuccessMessage extends ServerMessage {
  /// Creates a success message.
  SuccessMessage({
    required this.operation,
    required this.message,
  });

  /// The operation that succeeded.
  final String operation;

  /// Success message.
  final String message;

  @override
  ServerMessageType get type => ServerMessageType.success;

  /// Parse from JSON.
  factory SuccessMessage.fromJson(Map<String, dynamic> json) {
    return SuccessMessage(
      operation: json['operation'] as String? ?? '',
      message: json['message'] as String? ?? 'Success',
    );
  }
}

/// List of registered users.
class UsersMessage extends ServerMessage {
  /// Creates a users message.
  UsersMessage({required this.users});

  /// List of usernames.
  final List<String> users;

  @override
  ServerMessageType get type => ServerMessageType.users;

  /// Parse from JSON.
  factory UsersMessage.fromJson(Map<String, dynamic> json) {
    final usersList = json['users'] as List<dynamic>? ?? [];
    return UsersMessage(
      users: usersList.map((u) => u.toString()).toList(),
    );
  }
}

/// List of online users (response to online_users command).
class OnlineUsersResponseMessage extends ServerMessage {
  /// Creates an online users response message.
  OnlineUsersResponseMessage({required this.users});

  /// List of online usernames.
  final List<String> users;

  @override
  ServerMessageType get type => ServerMessageType.onlineUsers;

  /// Parse from JSON.
  factory OnlineUsersResponseMessage.fromJson(Map<String, dynamic> json) {
    final usersList = json['users'] as List<dynamic>? ?? [];
    return OnlineUsersResponseMessage(
      users: usersList.map((u) => u.toString()).toList(),
    );
  }
}

/// Signed prekey from key bundle.
class SignedPrekey {
  /// Creates a signed prekey.
  SignedPrekey({
    required this.keyId,
    required this.publicKey,
    required this.signature,
  });

  /// Unique key ID.
  final int keyId;

  /// X25519 public key (base64).
  final String publicKey;

  /// Ed25519 signature (base64).
  final String signature;

  /// Parse from JSON.
  factory SignedPrekey.fromJson(Map<String, dynamic> json) {
    return SignedPrekey(
      keyId: json['key_id'] as int? ?? 0,
      publicKey: json['public_key'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
    );
  }

  /// Get public key as bytes.
  Uint8List get publicKeyBytes => base64Decode(publicKey);

  /// Get signature as bytes.
  Uint8List get signatureBytes => base64Decode(signature);
}

/// One-time prekey from key bundle.
class ReceivedOneTimePrekey {
  /// Creates a one-time prekey.
  ReceivedOneTimePrekey({
    required this.keyId,
    required this.publicKey,
  });

  /// Unique key ID (base64 encoded binary from server).
  final String keyId;

  /// X25519 public key (base64).
  final String publicKey;

  /// Parse from JSON (legacy format with key_id/public_key).
  factory ReceivedOneTimePrekey.fromJson(Map<String, dynamic> json) {
    return ReceivedOneTimePrekey(
      keyId: (json['key_id'] as int? ?? 0).toString(),
      publicKey: json['public_key'] as String? ?? '',
    );
  }
  
  /// Parse from server JSON format (id/public as base64 strings).
  factory ReceivedOneTimePrekey.fromServerJson(Map<String, dynamic> json) {
    return ReceivedOneTimePrekey(
      keyId: json['id'] as String? ?? '',  // Server sends 'id' as base64
      publicKey: json['public'] as String? ?? '',  // Server sends 'public'
    );
  }

  /// Get public key as bytes.
  Uint8List get publicKeyBytes => base64Decode(publicKey);
  
  /// Get key ID as bytes.
  Uint8List get keyIdBytes => base64Decode(keyId);
}

/// Key bundle response for X3DH.
class KeyBundleMessage extends ServerMessage {
  /// Creates a key bundle message.
  KeyBundleMessage({
    required this.username,
    required this.identitySignKey,
    required this.identityDhKey,
    required this.signedPrekey,
    this.oneTimePrekey,
  });

  /// Username this bundle belongs to.
  final String username;

  /// Ed25519 identity signing key (base64).
  final String identitySignKey;

  /// X25519 identity DH key (base64).
  final String identityDhKey;

  /// The signed prekey.
  final SignedPrekey signedPrekey;

  /// Optional one-time prekey (may be null if exhausted).
  final ReceivedOneTimePrekey? oneTimePrekey;

  @override
  ServerMessageType get type => ServerMessageType.keyBundle;

  /// Parse from JSON.
  /// 
  /// Server sends:
  /// - user (not username)
  /// - identity_sign_public (not identity_sign_key)
  /// - identity_dh_public (not identity_dh_key)  
  /// - signed_prekey (base64 string, not nested object)
  /// - signed_prekey_signature (separate field)
  /// - one_time_prekey: { id: base64, public: base64 } or null
  factory KeyBundleMessage.fromJson(Map<String, dynamic> json) {
    final oneTimePrekeyJson = json['one_time_prekey'] as Map<String, dynamic>?;
    
    // Server sends signed_prekey and signed_prekey_signature as separate base64 strings
    // We need to construct a SignedPrekey from them
    // Note: Server doesn't send key_id for signed prekey in this response,
    // but we can extract it from the key_id field or default to 1
    final signedPrekeyPublic = json['signed_prekey'] as String? ?? '';
    final signedPrekeySignature = json['signed_prekey_signature'] as String? ?? '';
    
    return KeyBundleMessage(
      username: json['user'] as String? ?? '',  // Server sends 'user'
      identitySignKey: json['identity_sign_public'] as String? ?? '',  // Server sends 'identity_sign_public'
      identityDhKey: json['identity_dh_public'] as String? ?? '',  // Server sends 'identity_dh_public'
      signedPrekey: SignedPrekey(
        keyId: 1,  // Server doesn't send keyId for signed prekey in bundle response
        publicKey: signedPrekeyPublic,
        signature: signedPrekeySignature,
      ),
      oneTimePrekey: oneTimePrekeyJson != null
          ? ReceivedOneTimePrekey.fromServerJson(oneTimePrekeyJson)
          : null,
    );
  }

  /// Get identity signing key as bytes.
  Uint8List get identitySignKeyBytes => base64Decode(identitySignKey);

  /// Get identity DH key as bytes.
  Uint8List get identityDhKeyBytes => base64Decode(identityDhKey);
}

/// Incoming encrypted message (X3DH or Ratchet).
class IncomingMessage extends ServerMessage {
  /// Creates an incoming message.
  IncomingMessage({
    required this.messageType,
    required this.fromUser,
    required this.toUser,
    required this.rawData,
  });

  /// Type of encryption (x3dh or ratchet).
  final EncryptedMessageType messageType;

  /// Sender username.
  final String fromUser;

  /// Recipient username.
  final String toUser;

  /// Raw message data for processing.
  final Map<String, dynamic> rawData;

  @override
  ServerMessageType get type => ServerMessageType.message;

  /// Parse from JSON.
  /// 
  /// The server sends incoming encrypted messages in this format:
  /// ```json
  /// {
  ///   "type": "message",
  ///   "from": "sender",
  ///   "to": "recipient",
  ///   "message": {
  ///     "message_type": "x3dh" or "ratchet",
  ///     ... encrypted message fields
  ///   }
  /// }
  /// ```
  factory IncomingMessage.fromJson(Map<String, dynamic> json) {
    // The actual message data is nested under 'message' key
    final msgData = json['message'] as Map<String, dynamic>? ?? json;
    
    // message_type is inside the nested message, not at root level
    final msgTypeStr = msgData['message_type'] as String? ?? 'ratchet';
    
    return IncomingMessage(
      messageType:
          EncryptedMessageType.fromValue(msgTypeStr) ?? EncryptedMessageType.ratchet,
      fromUser: msgData['from'] as String? ?? '',
      toUser: msgData['to'] as String? ?? '',
      rawData: msgData,
    );
  }

  /// Check if this is an X3DH initial message.
  bool get isX3dh => messageType == EncryptedMessageType.x3dh;

  /// Check if this is a ratchet message.
  bool get isRatchet => messageType == EncryptedMessageType.ratchet;
}

/// Parsed X3DH incoming message.
class IncomingX3dhMessage {
  /// Creates an X3DH incoming message.
  IncomingX3dhMessage({
    required this.fromUser,
    required this.toUser,
    required this.identityKey,
    required this.ephemeralKey,
    this.usedOneTimePrekeyId,
    required this.ciphertext,
  });

  /// Sender username.
  final String fromUser;

  /// Recipient username.
  final String toUser;

  /// Sender's identity DH key (base64).
  final String identityKey;

  /// Ephemeral key (base64).
  final String ephemeralKey;

  /// ID of one-time prekey used (null if none).
  final int? usedOneTimePrekeyId;

  /// Encrypted ciphertext (base64).
  final String ciphertext;

  /// Parse from incoming message raw data.
  /// 
  /// Server sends X3DH messages with these field names:
  /// - from (not from_user)
  /// - to (not to_user)
  /// - ephemeral_public (not ephemeral_key or identity_key)
  /// - otpk_id (not used_one_time_prekey_id)
  /// - ciphertext
  /// - nonce
  /// - signature
  /// - metadata
  factory IncomingX3dhMessage.fromRawData(Map<String, dynamic> data) {
    return IncomingX3dhMessage(
      fromUser: data['from'] as String? ?? '',
      toUser: data['to'] as String? ?? '',
      identityKey: data['identity_key'] as String? ?? '',  // May need to check actual field name
      ephemeralKey: data['ephemeral_public'] as String? ?? '',
      usedOneTimePrekeyId: null,  // Server sends otpk_id as base64, handle separately
      ciphertext: data['ciphertext'] as String? ?? '',
    );
  }

  /// Get identity key as bytes.
  Uint8List get identityKeyBytes => base64Decode(identityKey);

  /// Get ephemeral key as bytes.
  Uint8List get ephemeralKeyBytes => base64Decode(ephemeralKey);

  /// Get ciphertext as bytes.
  Uint8List get ciphertextBytes => base64Decode(ciphertext);
}

/// Parsed ratchet incoming message.
class IncomingRatchetMessage {
  /// Creates a ratchet incoming message.
  IncomingRatchetMessage({
    required this.fromUser,
    required this.toUser,
    required this.dhPublic,
    required this.dhStep,
    required this.previousChainLength,
    required this.messageNumber,
    required this.ciphertext,
    required this.nonce,
  });

  /// Sender username.
  final String fromUser;

  /// Recipient username.
  final String toUser;

  /// Current ratchet DH public key (base64).
  final String dhPublic;

  /// DH ratchet step number.
  final int dhStep;

  /// Length of previous sending chain.
  final int previousChainLength;

  /// Message number in current chain.
  final int messageNumber;

  /// Encrypted ciphertext (base64).
  final String ciphertext;

  /// Nonce for decryption (base64).
  final String nonce;

  /// Parse from incoming message raw data.
  factory IncomingRatchetMessage.fromRawData(Map<String, dynamic> data) {
    return IncomingRatchetMessage(
      fromUser: data['from'] as String? ?? '',
      toUser: data['to'] as String? ?? '',
      dhPublic: data['dh_public'] as String? ?? '',
      dhStep: data['dh_step'] as int? ?? 0,
      previousChainLength: data['prev_chain_length'] as int? ?? 0,
      messageNumber: data['msg_number'] as int? ?? 0,
      ciphertext: data['ciphertext'] as String? ?? '',
      nonce: data['nonce'] as String? ?? '',
    );
  }

  /// Get DH public key as bytes.
  Uint8List get dhPublicBytes => base64Decode(dhPublic);

  /// Get ciphertext as bytes.
  Uint8List get ciphertextBytes => base64Decode(ciphertext);

  /// Get nonce as bytes.
  Uint8List get nonceBytes => base64Decode(nonce);
}

/// Message sent acknowledgment.
class MessageSentMessage extends ServerMessage {
  /// Creates a message sent acknowledgment.
  MessageSentMessage({
    required this.messageId,
    required this.toUser,
    required this.timestamp,
  });

  /// The message ID that was sent.
  final String messageId;

  /// The recipient username.
  final String toUser;

  /// Server timestamp when message was delivered.
  final int timestamp;

  @override
  ServerMessageType get type => ServerMessageType.messageSent;

  /// Parse from JSON.
  factory MessageSentMessage.fromJson(Map<String, dynamic> json) {
    return MessageSentMessage(
      messageId: json['message_id'] as String? ?? '',
      toUser: json['to_user'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  /// Get timestamp as DateTime.
  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
}

/// Error response from server.
class ErrorMessage extends ServerMessage {
  /// Creates an error message.
  ErrorMessage({
    required this.message,
    this.success = false,
  });

  /// Error message.
  final String message;

  /// Success flag (always false for errors).
  final bool success;

  @override
  ServerMessageType get type => ServerMessageType.error;

  /// Parse from JSON.
  factory ErrorMessage.fromJson(Map<String, dynamic> json) {
    return ErrorMessage(
      message: json['message'] as String? ?? 'Unknown error',
      success: json['success'] as bool? ?? false,
    );
  }
}

/// User online/offline status notification.
class UserStatusMessage extends ServerMessage {
  /// Creates a user status message.
  UserStatusMessage({
    required this.username,
    required this.isOnline,
  });

  /// The username.
  final String username;

  /// Whether the user is online.
  final bool isOnline;

  @override
  ServerMessageType get type => ServerMessageType.userStatus;

  /// Parse from JSON.
  factory UserStatusMessage.fromJson(Map<String, dynamic> json) {
    return UserStatusMessage(
      username: json['username'] as String? ?? '',
      isOnline: json['online'] as bool? ?? json['status'] == 'online',
    );
  }
}

/// Pending messages delivered notification.
class PendingMessagesDeliveredMessage extends ServerMessage {
  /// Creates a pending messages delivered message.
  PendingMessagesDeliveredMessage({required this.count});

  /// Number of pending messages delivered.
  final int count;

  @override
  ServerMessageType get type => ServerMessageType.pendingMessagesDelivered;

  /// Parse from JSON.
  factory PendingMessagesDeliveredMessage.fromJson(Map<String, dynamic> json) {
    return PendingMessagesDeliveredMessage(
      count: json['count'] as int? ?? 0,
    );
  }
}
