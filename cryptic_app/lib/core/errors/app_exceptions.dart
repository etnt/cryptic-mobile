// lib/core/errors/app_exceptions.dart
//
// Custom exception types for the application
//

/// Base class for all Cryptic application exceptions.
abstract class CrypticException implements Exception {
  /// Creates a new exception with the given message.
  const CrypticException(this.message);

  /// Human-readable description of the error.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Exception thrown when cryptographic operations fail.
class CryptoException extends CrypticException {
  /// Creates a new crypto exception.
  const CryptoException(super.message);
}

/// Exception thrown when key validation fails.
class InvalidKeyException extends CryptoException {
  /// Creates a new invalid key exception.
  const InvalidKeyException(super.message);
}

/// Exception thrown when signature verification fails.
class SignatureVerificationException extends CryptoException {
  /// Creates a new signature verification exception.
  const SignatureVerificationException([
    super.message = 'Signature verification failed',
  ]);
}

/// Exception thrown when message decryption fails.
class DecryptionException extends CryptoException {
  /// Creates a new decryption exception.
  const DecryptionException([
    super.message = 'Failed to decrypt message',
  ]);
}

/// Exception thrown when storage operations fail.
class StorageException extends CrypticException {
  /// Creates a new storage exception.
  const StorageException(super.message);
}

/// Exception thrown when secure storage is locked.
class StorageLockedExcpetion extends StorageException {
  /// Creates a new storage locked exception.
  const StorageLockedExcpetion([
    super.message = 'Secure storage is locked',
  ]);
}

/// Exception thrown when a required key is not found.
class KeyNotFoundException extends StorageException {
  /// Creates a new key not found exception.
  const KeyNotFoundException(String keyType) : super('Key not found: $keyType');
}

/// Exception thrown when network operations fail.
class NetworkException extends CrypticException {
  /// Creates a new network exception.
  const NetworkException(super.message);
}

/// Exception thrown when WebSocket connection fails.
class ConnectionException extends NetworkException {
  /// Creates a new connection exception.
  const ConnectionException([
    super.message = 'Failed to connect to server',
  ]);
}

/// Exception thrown when server returns an error.
class ServerException extends NetworkException {
  /// Creates a new server exception.
  const ServerException(super.message, {this.errorCode});

  /// Optional error code from server.
  final String? errorCode;
}

/// Exception thrown when protocol operations fail.
class ProtocolException extends CrypticException {
  /// Creates a new protocol exception.
  const ProtocolException(super.message);
}

/// Exception thrown when no session exists for a peer.
class NoSessionException extends ProtocolException {
  /// Creates a new no session exception.
  const NoSessionException(String peer) : super('No session with peer: $peer');
}

/// Exception thrown when message ordering is violated.
class MessageOrderException extends ProtocolException {
  /// Creates a new message order exception.
  const MessageOrderException([
    super.message = 'Message order violation detected',
  ]);
}
