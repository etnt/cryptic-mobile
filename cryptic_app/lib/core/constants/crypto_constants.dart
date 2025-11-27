// lib/core/constants/crypto_constants.dart
//
// Cryptographic constants used throughout the application
//

/// Constants for cryptographic operations.
///
/// These values match the Erlang Cryptic server implementation.
abstract class CryptoConstants {
  /// Ed25519 public key size in bytes.
  static const int ed25519PublicKeySize = 32;

  /// Ed25519 private key size in bytes.
  static const int ed25519PrivateKeySize = 64;

  /// Ed25519 signature size in bytes.
  static const int ed25519SignatureSize = 64;

  /// X25519 key size in bytes (both public and private).
  static const int x25519KeySize = 32;

  /// X25519 shared secret size in bytes.
  static const int x25519SharedSecretSize = 32;

  /// ChaCha20-Poly1305 key size in bytes.
  static const int chaChaKeySize = 32;

  /// ChaCha20-Poly1305 nonce size in bytes.
  static const int chaChaNonceSize = 12;

  /// ChaCha20-Poly1305 authentication tag size in bytes.
  static const int chaChaTagSize = 16;

  /// HKDF output key size in bytes.
  static const int hkdfOutputSize = 32;

  /// HKDF salt size in bytes (matches SHA-256 output).
  static const int hkdfSaltSize = 32;

  /// Info string for X3DH root key derivation.
  static const String x3dhInfo = 'X3DH';

  /// Info string for Double Ratchet chain key derivation.
  static const String ratchetChainInfo = 'CrypticRatchet';

  /// Info string for Double Ratchet message key derivation.
  static const String ratchetMessageInfo = 'CrypticMessage';

  /// Maximum number of skipped message keys to store per session.
  ///
  /// Prevents unbounded memory growth from out-of-order messages.
  static const int maxSkippedMessageKeys = 1000;

  /// Maximum message skip count for a single ratchet step.
  ///
  /// If more messages are skipped, session is considered compromised.
  static const int maxSkipPerStep = 100;
}
