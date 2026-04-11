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
///   "ciphertext": "<base64>",
///   "hmac": "<64 hex chars>"
/// }
/// ```
class EnrollmentEnvelope {
  const EnrollmentEnvelope({
    required this.version,
    required this.salt,
    required this.iv,
    required this.ciphertext,
    required this.hmac,
  });

  /// Payload format version.
  final int version;

  /// Argon2id salt (16 bytes from hex).
  final Uint8List salt;

  /// AES-256-CBC initialization vector (16 bytes from hex).
  final Uint8List iv;

  /// Encrypted payload (raw bytes from base64).
  final Uint8List ciphertext;

  /// HMAC-SHA256 over the base64-encoded ciphertext string (32 bytes from hex).
  final Uint8List hmac;

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
    final ciphertextB64 = map['ciphertext'] as String?;
    final hmacHex = map['hmac'] as String?;

    if (saltHex == null ||
        ivHex == null ||
        ciphertextB64 == null ||
        hmacHex == null) {
      throw const EnrollmentException('Missing required fields in envelope');
    }

    return EnrollmentEnvelope(
      version: version,
      salt: _hexDecode(saltHex),
      iv: _hexDecode(ivHex),
      ciphertext: base64.decode(ciphertextB64),
      hmac: _hexDecode(hmacHex),
    );
  }

  /// Get the base64 ciphertext string for HMAC verification.
  ///
  /// We need the original base64 string (not the decoded bytes) because
  /// the HMAC is computed over the base64 representation.
  String get ciphertextBase64 => base64.encode(ciphertext);

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
  /// Supports both compact keys (v2) and verbose keys (v1 GPG fallback).
  factory EnrollmentPayload.fromMap(Map<String, dynamic> map) {
    // Username
    final username =
        map['u'] as String? ?? map['username'] as String?;
    if (username == null || username.isEmpty) {
      throw const EnrollmentException('Missing username in payload');
    }

    // Server config
    final server = map['s'] as Map<String, dynamic>? ??
        map['server'] as Map<String, dynamic>?;
    if (server == null) {
      throw const EnrollmentException('Missing server config in payload');
    }
    final host =
        server['h'] as String? ?? server['host'] as String?;
    final port =
        server['p'] as int? ?? server['port'] as int? ?? 8443;
    if (host == null || host.isEmpty) {
      throw const EnrollmentException('Missing server host in payload');
    }

    // Enrollment key
    final ekB64 = map['ek'] as String?;
    if (ekB64 == null) {
      throw const EnrollmentException(
        'Missing enrollment key (ek) in payload',
      );
    }
    final enrollmentKey = base64.decode(ekB64);
    if (enrollmentKey.length != 64) {
      throw EnrollmentException(
        'Invalid enrollment key size: ${enrollmentKey.length} (expected 64)',
      );
    }

    // CA fingerprint
    final caFp = map['cf'] as String?;
    if (caFp == null || caFp.length != 64) {
      throw const EnrollmentException(
        'Missing or invalid CA fingerprint (cf) in payload',
      );
    }

    // Expiry
    final expiresAtUnix = map['x'] as int? ?? map['expires_at'] as int?;
    if (expiresAtUnix == null) {
      throw const EnrollmentException('Missing expiry (x) in payload');
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

  /// Securely erase the enrollment key from memory.
  void eraseKey() {
    enrollmentSecretKey.fillRange(0, enrollmentSecretKey.length, 0);
  }
}

/// Exception thrown during enrollment operations.
class EnrollmentException extends CrypticException {
  const EnrollmentException(super.message);
}
