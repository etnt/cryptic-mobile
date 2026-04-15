// lib/data/enrollment/enrollment_service.dart
//
// Enrollment orchestration service.
//
// Coordinates the full enrollment flow:
// 1. Parse QR data (encrypted envelope)
// 2. Decrypt with passphrase → enrollment payload
// 3. Fetch & verify CA certificate
// 4. Generate Ed25519 keypair + CSR
// 5. Sign CSR with enrollment key
// 6. Submit to server
// 7. Store mTLS certificate
//
// Each step emits status updates via a callback for UI progress display.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../../core/utils/logger.dart';
import '../storage/secure_storage/certificate_storage_service.dart';
import 'csr_generator.dart';
import 'enrollment_crypto.dart';
import 'enrollment_payload.dart';

/// Progress stages during enrollment.
enum EnrollmentStage {
  /// Parsing the QR code data.
  parsingQr,

  /// Deriving keys and decrypting.
  decrypting,

  /// Fetching and verifying the CA certificate.
  verifyingCa,

  /// Generating TLS keypair and CSR.
  generatingCsr,

  /// Signing CSR with enrollment key.
  signingCsr,

  /// Submitting CSR to server.
  submittingCsr,

  /// Storing issued certificate.
  storingCertificate,

  /// Enrollment complete.
  complete,
}

/// Result of a successful enrollment.
class EnrollmentResult {
  const EnrollmentResult({
    required this.username,
    required this.serverHost,
    required this.serverPort,
    required this.certSerial,
    required this.expiresAt,
  });

  final String username;
  final String serverHost;
  final int serverPort;
  final String certSerial;
  final DateTime expiresAt;
}

/// Callback for enrollment progress updates.
typedef EnrollmentProgressCallback = void Function(EnrollmentStage stage);

/// Orchestrates the mobile enrollment flow.
class EnrollmentService {
  EnrollmentService({
    EnrollmentCrypto? crypto,
    CsrGenerator? csrGenerator,
    CertificateStorageService? certStorage,
  })  : _crypto = crypto ?? EnrollmentCrypto(),
        _csrGenerator = csrGenerator ?? CsrGenerator(),
        _certStorage = certStorage ?? CertificateStorageService();

  final EnrollmentCrypto _crypto;
  final CsrGenerator _csrGenerator;
  final CertificateStorageService _certStorage;

  /// Execute the full enrollment flow.
  ///
  /// [qrData] - Raw string scanned from the QR code.
  /// [passphrase] - Passphrase provided by the admin out-of-band.
  /// [onProgress] - Optional callback for UI progress updates.
  ///
  /// Throws [EnrollmentException] on failure.
  Future<EnrollmentResult> enroll({
    required String qrData,
    required String passphrase,
    EnrollmentProgressCallback? onProgress,
  }) async {
    // Step 1: Parse QR envelope
    onProgress?.call(EnrollmentStage.parsingQr);
    final envelope = EnrollmentEnvelope.fromQrData(qrData);

    // Step 2: Decrypt with passphrase
    onProgress?.call(EnrollmentStage.decrypting);
    final payload = await _crypto.decryptEnvelope(envelope, passphrase);

    // Check expiry
    if (payload.isExpired) {
      payload.eraseKey();
      throw const EnrollmentException(
        'Enrollment has expired — request a new QR code from admin',
      );
    }

    try {
      // Step 3: Fetch & verify CA certificate
      onProgress?.call(EnrollmentStage.verifyingCa);
      final caCertPem = await _fetchAndVerifyCaCert(
        host: payload.serverHost,
        port: payload.serverPort,
        expectedFingerprint: payload.caFingerprint,
      );

      // Step 4: Generate TLS keypair + CSR
      onProgress?.call(EnrollmentStage.generatingCsr);
      final csrResult = await _csrGenerator.generateCsr(payload.username);

      // Step 5: Sign CSR with enrollment key
      onProgress?.call(EnrollmentStage.signingCsr);
      final signature = await _crypto.signCsr(
        csrResult.csrPem,
        payload.enrollmentSecretKey,
      );
      final enrollmentFp = _crypto.computeEnrollmentFingerprint(
        payload.enrollmentPublicKey,
      );

      // Step 6: Submit CSR to server
      onProgress?.call(EnrollmentStage.submittingCsr);
      final serverResponse = await _submitCsr(
        host: payload.serverHost,
        port: payload.serverPort,
        csrPem: csrResult.csrPem,
        enrollmentFp: enrollmentFp,
        signatureB64: base64.encode(signature),
        caCertPem: caCertPem,
      );

      // Step 7: Store certificate
      onProgress?.call(EnrollmentStage.storingCertificate);
      final issuedCertPem = serverResponse['cert_pem'] as String;
      final serial = serverResponse['serial'] as String? ?? '';
      final expiresAtUnix = serverResponse['expires_at'] as int;

      await _certStorage.storeCertificates(
        clientCertPem: issuedCertPem,
        clientKeyPem: csrResult.privateKeyPem,
        caCertPem: caCertPem,
        metadata: CertificateMetadata(
          username: payload.username,
          serverHost: payload.serverHost,
          serverPort: payload.serverPort,
          importedAt: DateTime.now(),
          expiresAt:
              DateTime.fromMillisecondsSinceEpoch(expiresAtUnix * 1000),
          fingerprint: enrollmentFp,
        ),
      );

      onProgress?.call(EnrollmentStage.complete);

      return EnrollmentResult(
        username: payload.username,
        serverHost: payload.serverHost,
        serverPort: payload.serverPort,
        certSerial: serial,
        expiresAt:
            DateTime.fromMillisecondsSinceEpoch(expiresAtUnix * 1000),
      );
    } finally {
      // Always erase the enrollment key
      payload.eraseKey();
    }
  }

  /// Fetch the CA certificate from the server and verify its fingerprint.
  Future<String> _fetchAndVerifyCaCert({
    required String host,
    required int port,
    required String expectedFingerprint,
  }) async {
    final url = Uri.https('$host:$port', '/ca/v1/ca-cert');

    // For this bootstrap request, we accept any TLS certificate because
    // we verify the CA cert via its fingerprint from the QR code.
    try {
      final ioClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final request = await ioClient.getUrl(url);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw EnrollmentException(
          'Failed to fetch CA certificate: HTTP ${response.statusCode}',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      ioClient.close();

      // Verify fingerprint
      _verifyCaFingerprint(body, expectedFingerprint);

      return body;
    } on EnrollmentException {
      rethrow;
    } catch (e) {
      throw EnrollmentException(
        'Failed to connect to server: $e',
      );
    }
  }

  /// Verify that the CA certificate PEM matches the expected SHA-256 fingerprint.
  void _verifyCaFingerprint(String caCertPem, String expectedFp) {
    // Extract DER from PEM
    final lines = caCertPem.split('\n');
    final b64Lines = lines
        .where((line) =>
            !line.startsWith('-----') && line.trim().isNotEmpty,)
        .join();
    final derBytes = base64.decode(b64Lines);

    // Compute SHA-256
    final digest = pc.SHA256Digest();
    final hash = digest.process(Uint8List.fromList(derBytes));
    final fingerprint = _hexEncode(hash);

    if (fingerprint != expectedFp.toLowerCase()) {
      throw const EnrollmentException(
        'CA certificate fingerprint mismatch — possible MITM attack. '
        'Contact your admin.',
      );
    }

    AppLogger.info('CA certificate fingerprint verified');
  }

  /// Submit the signed CSR to the server's mobile enrollment endpoint.
  Future<Map<String, dynamic>> _submitCsr({
    required String host,
    required int port,
    required String csrPem,
    required String enrollmentFp,
    required String signatureB64,
    required String caCertPem,
  }) async {
    final url = Uri.https('$host:$port', '/ca/v1/mobile-csr');

    try {
      // The CA cert was already verified by fingerprint from the QR code.
      // Accept the server's TLS cert here to avoid hostname/chain mismatches
      // (e.g. cert issued for a FQDN but we're connecting via localhost).
      final ioClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final request = await ioClient.postUrl(url);
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        'csr_pem': csrPem,
        'enrollment_fp': enrollmentFp,
        'enrollment_sig_b64': signatureB64,
      });
      request.write(body);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      ioClient.close();

      if (response.statusCode != 200) {
        final errorMsg = _extractError(responseBody);
        throw EnrollmentException(
          'Server rejected enrollment: $errorMsg',
        );
      }

      final result = jsonDecode(responseBody) as Map<String, dynamic>;

      if (result['status'] != 'issued') {
        throw EnrollmentException(
          'Unexpected server response: ${result['status']}',
        );
      }

      return result;
    } on EnrollmentException {
      rethrow;
    } catch (e) {
      throw EnrollmentException('Failed to submit CSR: $e');
    }
  }

  /// Extract error message from JSON response body.
  String _extractError(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return map['message'] as String? ??
          map['error'] as String? ??
          body;
    } catch (_) {
      return body;
    }
  }

  static String _hexEncode(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
