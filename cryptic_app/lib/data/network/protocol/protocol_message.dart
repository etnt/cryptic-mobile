/// Protocol message types for Cryptic WebSocket communication.
///
/// All messages follow JSON format with a `type` field that identifies
/// the message category. This file defines the base types and enums.
library;

import 'dart:convert';

/// Base class for all protocol messages.
abstract class ProtocolMessage {
  /// The message type identifier.
  String get type;

  /// Convert to JSON map for serialization.
  Map<String, dynamic> toJson();

  /// Serialize to JSON string.
  String toJsonString() => jsonEncode(toJson());
}

/// Client-to-server message types.
enum ClientMessageType {
  /// Upload identity keys for initial setup.
  uploadIdentityKeys('upload_identity_keys'),

  /// Upload one-time prekeys bundle.
  uploadPrekeyBundle('upload_prekey_bundle'),

  /// Request another user's key bundle for X3DH.
  getKeyBundle('get_key_bundle'),

  /// Send X3DH initial message.
  x3dh('x3dh'),

  /// Send ratchet message (ongoing conversation).
  ratchet('ratchet'),

  /// Request list of registered users (admin only).
  listUsers('list_users'),

  /// Request list of online users (non-admin).
  onlineUsers('online_users'),

  /// Send a message (higher-level, engine encrypts).
  sendMessage('send_message'),

  /// Request delivery of pending (offline) messages.
  requestPendingMessages('request_pending_messages'),

  /// Acknowledge receipt of a delivered message (store-and-forward).
  messageAck('message_ack');

  const ClientMessageType(this.value);

  /// The wire format value.
  final String value;

  /// Parse from wire format.
  static ClientMessageType? fromValue(String value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Server-to-client message types.
enum ServerMessageType {
  /// Welcome message on connection.
  welcome('welcome'),

  /// Success response for operations.
  success('success'),

  /// List of registered users (response to list_users).
  users('users'),

  /// List of online users (response to online_users).
  onlineUsers('online_users'),

  /// Key bundle response (for X3DH).
  keyBundle('key_bundle'),

  /// Incoming encrypted message.
  message('message'),

  /// Message sent acknowledgment.
  messageSent('message_sent'),

  /// Error response.
  error('error'),

  /// User online/offline status.
  userStatus('user_status'),

  /// Pending messages delivered count.
  pendingMessagesDelivered('pending_messages_delivered');

  const ServerMessageType(this.value);

  /// The wire format value.
  final String value;

  /// Parse from wire format.
  static ServerMessageType? fromValue(String value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Encrypted message types (X3DH initial or ratchet).
enum EncryptedMessageType {
  /// X3DH initial message (establishing session).
  x3dh('x3dh'),

  /// Ratchet message (ongoing session).
  ratchet('ratchet');

  const EncryptedMessageType(this.value);

  /// The wire format value.
  final String value;

  /// Parse from wire format.
  static EncryptedMessageType? fromValue(String value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}
