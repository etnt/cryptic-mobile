/// Protocol message codec for encoding/decoding WebSocket messages.
///
/// Provides utilities for converting between protocol messages and JSON.
library;

import 'dart:convert';

import 'protocol_message.dart';
import 'server_messages.dart';

/// Codec for encoding and decoding protocol messages.
class ProtocolCodec {
  /// Encode a client message to JSON string.
  static String encode(ProtocolMessage message) => message.toJsonString();

  /// Decode a server message from JSON string.
  ///
  /// Returns null if the message cannot be decoded.
  static ServerMessage? decode(String jsonString) =>
      ServerMessage.fromJsonString(jsonString);

  /// Decode a server message from JSON map.
  ///
  /// Returns null if the message cannot be decoded.
  static ServerMessage? decodeMap(Map<String, dynamic> json) =>
      ServerMessage.fromJson(json);

  /// Parse raw JSON string to map.
  ///
  /// Returns null if parsing fails.
  static Map<String, dynamic>? parseJson(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Check if a message type is a known server message type.
  static bool isKnownServerType(String type) =>
      ServerMessageType.fromValue(type) != null;

  /// Check if a message type is a known client message type.
  static bool isKnownClientType(String type) =>
      ClientMessageType.fromValue(type) != null;
}

/// Extension methods for easier message handling.
extension IncomingMessageExtension on IncomingMessage {
  /// Parse as X3DH message if applicable.
  IncomingX3dhMessage? asX3dh() {
    if (!isX3dh) return null;
    return IncomingX3dhMessage.fromRawData(rawData);
  }

  /// Parse as ratchet message if applicable.
  IncomingRatchetMessage? asRatchet() {
    if (!isRatchet) return null;
    return IncomingRatchetMessage.fromRawData(rawData);
  }
}
