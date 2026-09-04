// lib/data/storage/secure_storage/certificate_storage_service.dart
//
// Certificate Storage Service - Secure storage for mTLS certificates
//

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_exceptions.dart';
import 'secure_storage_service.dart';

/// Storage keys for certificate data.
abstract class CertStorageKeys {
  /// Prefix for certificate storage entries.
  static const prefix = 'cryptic_cert_';

  /// Client certificate (PEM).
  static const clientCert = '${prefix}client_cert';

  /// Client private key (PEM).
  static const clientKey = '${prefix}client_key';

  /// CA certificate (PEM).
  static const caCert = '${prefix}ca_cert';

  /// Certificate metadata.
  static const metadata = '${prefix}metadata';
}

/// Metadata about stored certificates.
class CertificateMetadata {
  /// Creates from map.
  factory CertificateMetadata.fromMap(Map<String, dynamic> map) {
    return CertificateMetadata(
      username: map['username'] as String,
      serverHost: map['server_host'] as String,
      serverPort: map['server_port'] as int,
      importedAt:
          DateTime.fromMillisecondsSinceEpoch(map['imported_at'] as int),
      expiresAt: map['expires_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expires_at'] as int)
          : null,
      fingerprint: map['fingerprint'] as String?,
    );
  }

  /// Creates certificate metadata.
  const CertificateMetadata({
    required this.username,
    required this.serverHost,
    required this.serverPort,
    required this.importedAt,
    this.expiresAt,
    this.fingerprint,
  });

  /// Username associated with the certificate.
  final String username;

  /// Server host this certificate is for.
  final String serverHost;

  /// Server port.
  final int serverPort;

  /// When the certificate was imported.
  final DateTime importedAt;

  /// When the certificate expires (if known).
  final DateTime? expiresAt;

  /// Certificate fingerprint (SHA-256).
  final String? fingerprint;

  /// Converts to map for serialization.
  Map<String, dynamic> toMap() => {
        'username': username,
        'server_host': serverHost,
        'server_port': serverPort,
        'imported_at': importedAt.millisecondsSinceEpoch,
        'expires_at': expiresAt?.millisecondsSinceEpoch,
        'fingerprint': fingerprint,
      };

  /// Checks if the certificate has expired.
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Days until expiration (null if no expiry set).
  int? get daysUntilExpiry {
    if (expiresAt == null) return null;
    return expiresAt!.difference(DateTime.now()).inDays;
  }
}

/// Service for storing mTLS certificates.
///
/// Handles storage and retrieval of:
/// - Client certificate (PEM format)
/// - Client private key (PEM format)
/// - CA certificate for server verification
class CertificateStorageService {
  /// Creates a certificate storage service.
  CertificateStorageService({
    SecureStorageService? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageService();

  final SecureStorageService _secureStorage;

  // ─────────────────────────────────────────────────────────────────────────
  // Certificate Storage
  // ─────────────────────────────────────────────────────────────────────────

  /// Stores client certificate and key.
  ///
  /// [clientCertPem] - Client certificate in PEM format.
  /// [clientKeyPem] - Client private key in PEM format.
  /// [caCertPem] - CA certificate for server verification.
  /// [metadata] - Certificate metadata.
  Future<void> storeCertificates({
    required String clientCertPem,
    required String clientKeyPem,
    required String caCertPem,
    required CertificateMetadata metadata,
  }) async {
    try {
      await _secureStorage.write(
        key: CertStorageKeys.clientCert,
        value: clientCertPem,
      );
      await _secureStorage.write(
        key: CertStorageKeys.clientKey,
        value: clientKeyPem,
      );
      await _secureStorage.write(
        key: CertStorageKeys.caCert,
        value: caCertPem,
      );
      await _secureStorage.writeJson(
        key: CertStorageKeys.metadata,
        value: metadata.toMap(),
      );
    } catch (e) {
      throw StorageException('Failed to store certificates: $e');
    }
  }

  /// Loads the client certificate (PEM).
  Future<String?> loadClientCertificate() async =>
      await _secureStorage.read(key: CertStorageKeys.clientCert);

  /// Loads the client private key (PEM).
  Future<String?> loadClientKey() async =>
      await _secureStorage.read(key: CertStorageKeys.clientKey);

  /// Loads the CA certificate (PEM).
  Future<String?> loadCaCertificate() async =>
      await _secureStorage.read(key: CertStorageKeys.caCert);

  /// Loads certificate metadata.
  Future<CertificateMetadata?> loadMetadata() async {
    final map = await _secureStorage.readJson(key: CertStorageKeys.metadata);
    if (map == null) return null;
    return CertificateMetadata.fromMap(map);
  }

  /// Checks if certificates are stored.
  Future<bool> hasCertificates() async =>
      await _secureStorage.containsKey(key: CertStorageKeys.clientCert);

  /// Deletes all stored certificates.
  Future<void> deleteCertificates() async {
    await _secureStorage.delete(key: CertStorageKeys.clientCert);
    await _secureStorage.delete(key: CertStorageKeys.clientKey);
    await _secureStorage.delete(key: CertStorageKeys.caCert);
    await _secureStorage.delete(key: CertStorageKeys.metadata);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SecurityContext Creation
  // ─────────────────────────────────────────────────────────────────────────

  /// Creates a [SecurityContext] for mTLS connections.
  ///
  /// Returns null if certificates are not stored.
  Future<SecurityContext?> createSecurityContext() async {
    final clientCert = await loadClientCertificate();
    final clientKey = await loadClientKey();
    final caCert = await loadCaCertificate();

    if (clientCert == null || clientKey == null || caCert == null) {
      return null;
    }

    try {
      final context = SecurityContext();

      // Load CA for server verification
      context.setTrustedCertificatesBytes(utf8.encode(caCert));

      // Load client certificate chain
      context.useCertificateChainBytes(utf8.encode(clientCert));

      // Load client private key
      context.usePrivateKeyBytes(utf8.encode(clientKey));

      return context;
    } catch (e) {
      throw StorageException('Failed to create SecurityContext: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Import from Files
  // ─────────────────────────────────────────────────────────────────────────

  /// Imports certificates from files.
  ///
  /// [clientCertPath] - Path to client certificate PEM file.
  /// [clientKeyPath] - Path to client private key PEM file.
  /// [caCertPath] - Path to CA certificate PEM file.
  /// [username] - Username for metadata.
  /// [serverHost] - Server host for metadata.
  /// [serverPort] - Server port for metadata.
  Future<void> importFromFiles({
    required String clientCertPath,
    required String clientKeyPath,
    required String caCertPath,
    required String username,
    required String serverHost,
    required int serverPort,
  }) async {
    try {
      final clientCertFile = File(clientCertPath);
      final clientKeyFile = File(clientKeyPath);
      final caCertFile = File(caCertPath);

      final clientCertPem = await clientCertFile.readAsString();
      final clientKeyPem = await clientKeyFile.readAsString();
      final caCertPem = await caCertFile.readAsString();

      final metadata = CertificateMetadata(
        username: username,
        serverHost: serverHost,
        serverPort: serverPort,
        importedAt: DateTime.now(),
      );

      await storeCertificates(
        clientCertPem: clientCertPem,
        clientKeyPem: clientKeyPem,
        caCertPem: caCertPem,
        metadata: metadata,
      );
    } catch (e) {
      throw StorageException('Failed to import certificates: $e');
    }
  }

  /// Imports certificates from asset bundles (for bundled certs).
  ///
  /// [clientCertBytes] - Client certificate bytes.
  /// [clientKeyBytes] - Client private key bytes.
  /// [caCertBytes] - CA certificate bytes.
  /// [metadata] - Certificate metadata.
  Future<void> importFromBytes({
    required Uint8List clientCertBytes,
    required Uint8List clientKeyBytes,
    required Uint8List caCertBytes,
    required CertificateMetadata metadata,
  }) async {
    await storeCertificates(
      clientCertPem: utf8.decode(clientCertBytes),
      clientKeyPem: utf8.decode(clientKeyBytes),
      caCertPem: utf8.decode(caCertBytes),
      metadata: metadata,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Export/Backup
  // ─────────────────────────────────────────────────────────────────────────

  /// Exports certificates to a directory.
  ///
  /// Returns the directory path where certificates were exported.
  Future<String> exportToDirectory() async {
    final clientCert = await loadClientCertificate();
    final clientKey = await loadClientKey();
    final caCert = await loadCaCertificate();
    final metadata = await loadMetadata();

    if (clientCert == null || clientKey == null || caCert == null) {
      throw const StorageException('No certificates to export');
    }

    final directory = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${directory.path}/cryptic_certs_export');
    await exportDir.create(recursive: true);

    final prefix = metadata?.username ?? 'client';

    await File('${exportDir.path}/$prefix.crt').writeAsString(clientCert);
    await File('${exportDir.path}/$prefix.key').writeAsString(clientKey);
    await File('${exportDir.path}/ca.crt').writeAsString(caCert);

    if (metadata != null) {
      await File('${exportDir.path}/metadata.json')
          .writeAsString(jsonEncode(metadata.toMap()));
    }

    return exportDir.path;
  }
}
