// lib/data/enrollment/enrollment_payload.dart
//
// Enrollment payload models for mobile onboarding.
//
// The encrypted QR code contains a v2 enrollment payload with:
// - Username and server configuration
// - Ed25519 enrollment secret key (for CSR signing)
// - CA certificate fingerprint (for trust pinning)
// - Expiration timestamp

import 'dart:convert';
import 'dart:typed_data';

import '../../core/errors/app_exceptions.dart';

/// The outer encrypted envelope from the QR code.
///
/// Format:
/// ```json
/// {
///   "v": 2,
///   "salt": "<32 hex chars>",
///   "iv": "<32 hex chars>",
///   "ct": "<base64>",
///   "hmac": "<64 hex chars>"
/// }
/// ```
class EnrollmentEnvelope {

  /// Parse from QR code JSON string.
  factory EnrollmentEnvelope.fromQrData(String qrData) {
    try {
      final map = jsonDecode(qrData) as Map<String, dynamic>;
      return EnrollmentEnvelope.fromMap(map);
    } on FormatException catch (e) {
      throw EnrollmentException('Invalid QR code format: $e');
    }
  }

  /// Parse from decoded JSON map.
  factory EnrollmentEnvelope.fromMap(Map<String, dynamic> map) {
    final version = map['v'] as int? ?? map['version'] as int? ?? 0;
    if (version < 1 || version > 2) {
      throw EnrollmentException(
        'Unsupported enrollment version: $version',
      );
    }

    final saltHex = map['salt'] as String?;
    final ivHex = map['iv'] as String?;
    final ciphertextB64 = map['ct'] as String?;
    final hmacHex = map['hmac'] as String?;

    if (saltHex == null ||
        ivHex == null ||
        ciphertextB64 == null ||
        hmacHex == null) {
      throw const EnrollmentException('Missing required fields in envelope');
    }

    return EnrollmentEnvelope(
      version: version,
      saltHex: saltHex,
      iv: _hexDecode(ivHex),
      ciphertext: base64.decode(ciphertextB64),
      ciphertextBase64: ciphertextB64,
      hmac: _hexDecode(hmacHex),
    );
  }
  const EnrollmentEnvelope({
    required this.version,
    required this.saltHex,
    required this.iv,
    required this.ciphertext,
    required this.ciphertextBase64,
    required this.hmac,
  });

  /// Payload format version.
  final int version;

  /// Argon2id salt as the original hex string.
  ///
  /// The CLI `argon2` tool uses the hex string directly as ASCII bytes
  /// for the salt, so we must preserve the original string form.
  final String saltHex;

  /// AES-256-CBC initialization vector (16 bytes from hex).
  final Uint8List iv;

  /// Encrypted payload (raw bytes from base64).
  final Uint8List ciphertext;

  /// Original base64-encoded ciphertext string from the QR envelope.
  ///
  /// The HMAC is computed over this exact string, so we preserve it
  /// rather than re-encoding from decoded bytes.
  final String ciphertextBase64;

  /// HMAC-SHA256 over the base64-encoded ciphertext string (32 bytes from hex).
  final Uint8List hmac;

  static Uint8List _hexDecode(String hex) {
    if (hex.length.isOdd) {
      throw EnrollmentException('Invalid hex string length: ${hex.length}');
    }
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      bytes[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }
}

/// Decrypted enrollment payload.
///
/// Contains all information the mobile client needs to enroll.
class EnrollmentPayload {

  /// Parse from decrypted JSON.
  factory EnrollmentPayload.fromJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return EnrollmentPayload.fromMap(map);
    } on FormatException catch (e) {
      throw EnrollmentException('Invalid enrollment payload: $e');
    }
  }

  /// Parse from decoded JSON map.
  ///
  /// The server's `cryptic-onboard create-mobile-enrollment` produces:
  /// ```json
  /// {
  ///   "username": "alice",
  ///   "server_host": "localhost",
  ///   "server_port": 8443,
  ///   "ca_fingerprint": "<64 hex>",
  ///   "enrollment_sec": "<base64 of 64-byte Ed25519 secret>",
  ///   "expires_at": <unix seconds>
  /// }
  /// ```
  factory EnrollmentPayload.fromMap(Map<String, dynamic> map) {
    // Username
    final username = map['username'] as String?;
    if (username == null || username.isEmpty) {
      throw const EnrollmentException('Missing username in payload');
    }

    // Server config (top-level keys from the onboard tool).
    // Server host/port from QR payload. These may be overridden by the user
    // in the enrollment UI (e.g. when the admin used localhost but the mobile
    // device needs a public hostname to reach the server).
    final host = map['server_host'] as String?;
    final port = map['server_port'] as int? ?? 8443;
    if (host == null || host.isEmpty) {
      throw const EnrollmentException('Missing server_host in payload');
    }

    // Enrollment Ed25519 keys.
    // The onboard tool stores the DER-encoded private key in enrollment_sec
    // and the raw 32-byte public key in enrollment_pub. We extract the
    // 32-byte seed from the DER and combine with the public key to form the
    // 64-byte NaCl-style secret key expected by the Ed25519 signing code.
    final secB64 = map['enrollment_sec'] as String?;
    final pubB64 = map['enrollment_pub'] as String?;
    if (secB64 == null || pubB64 == null) {
      throw const EnrollmentException(
        'Missing enrollment_sec or enrollment_pub in payload',
      );
    }
    final secDer = base64.decode(secB64);
    final pubRaw = base64.decode(pubB64);
    if (pubRaw.length != 32) {
      throw EnrollmentException(
        'Invalid enrollment public key size: ${pubRaw.length} (expected 32)',
      );
    }
    // The 32-byte seed is the last 32 bytes of the PKCS#8 DER encoding.
    final seed = secDer.sublist(secDer.length - 32);
    final enrollmentKey = Uint8List(64)
      ..setRange(0, 32, seed)
      ..setRange(32, 64, pubRaw);

    // CA fingerprint
    final caFp = map['ca_fingerprint'] as String?;
    if (caFp == null || caFp.length != 64) {
      throw const EnrollmentException(
        'Missing or invalid ca_fingerprint in payload',
      );
    }

    // Expiry
    final expiresAtUnix = map['expires_at'] as int?;
    if (expiresAtUnix == null) {
      throw const EnrollmentException('Missing expires_at in payload');
    }

    return EnrollmentPayload(
      username: username,
      serverHost: host,
      serverPort: port,
      enrollmentSecretKey: Uint8List.fromList(enrollmentKey),
      caFingerprint: caFp,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtUnix * 1000),
    );
  }
  const EnrollmentPayload({
    required this.username,
    required this.serverHost,
    required this.serverPort,
    required this.enrollmentSecretKey,
    required this.caFingerprint,
    required this.expiresAt,
  });

  /// The username assigned by the admin.
  final String username;

  /// Server hostname.
  final String serverHost;

  /// Server port.
  final int serverPort;

  /// Ed25519 enrollment secret key (64 bytes: 32-byte seed || 32-byte pub).
  final Uint8List enrollmentSecretKey;

  /// SHA-256 fingerprint of the CA certificate (hex string, 64 chars).
  final String caFingerprint;

  /// When this enrollment expires.
  final DateTime expiresAt;

  /// Whether this enrollment has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Extract the 32-byte Ed25519 public key from the secret key.
  Uint8List get enrollmentPublicKey => enrollmentSecretKey.sublist(32, 64);

  /// Securely erase the enrollment key from memory.
  void eraseKey() {
    enrollmentSecretKey.fillRange(0, enrollmentSecretKey.length, 0);
  }
}

/// Exception thrown during enrollment operations.
class EnrollmentException extends CrypticException {
  const EnrollmentException(super.message);
}
