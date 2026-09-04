/// mTLS (mutual TLS) configuration for secure WebSocket connections.
///
/// Provides certificate loading and SecurityContext configuration
/// for mutual TLS authentication with the Cryptic server.
library;

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import '../../storage/secure_storage/certificate_storage_service.dart';

/// Loaded certificate bundle.
class CertificateBundle {
  /// Creates a certificate bundle.
  const CertificateBundle({
    required this.clientCertificate,
    required this.clientKey,
    required this.caCertificate,
  });

  /// Client certificate in PEM format.
  final Uint8List clientCertificate;

  /// Client private key in PEM format.
  final Uint8List clientKey;

  /// CA certificate for server validation.
  final Uint8List caCertificate;
}

/// Configuration for mTLS WebSocket connections.
///
/// Holds all the certificates and keys needed for mutual TLS:
/// - Client certificate (proves client identity to server)
/// - Client private key (for TLS handshake)
/// - CA certificate (validates server certificate)
class MtlsConfig {
  /// Creates an mTLS configuration.
  MtlsConfig({
    required this.clientCertificate,
    required this.clientPrivateKey,
    required this.caCertificate,
    this.serverHost,
    this.serverPort,
    this.password,
  });

  /// Client certificate in PEM format.
  final Uint8List clientCertificate;

  /// Client private key in PEM format.
  final Uint8List clientPrivateKey;

  /// CA certificate for validating the server.
  final Uint8List caCertificate;

  /// Optional server hostname (for SNI).
  final String? serverHost;

  /// Optional server port.
  final int? serverPort;

  /// Optional password for encrypted private key.
  final String? password;

  /// Load mTLS configuration from certificate storage.
  ///
  /// Loads certificates previously stored by [CertificateStorageService].
  static Future<MtlsConfig?> fromStorage({
    required CertificateStorageService certificateStorage,
    required String serverHost,
    required int serverPort,
    String? password,
  }) async {
    final clientCertPem = await certificateStorage.loadClientCertificate();
    final clientKeyPem = await certificateStorage.loadClientKey();
    final caCertPem = await certificateStorage.loadCaCertificate();

    if (clientCertPem == null || clientKeyPem == null || caCertPem == null) {
      return null;
    }

    return MtlsConfig(
      clientCertificate: Uint8List.fromList(utf8.encode(clientCertPem)),
      clientPrivateKey: Uint8List.fromList(utf8.encode(clientKeyPem)),
      caCertificate: Uint8List.fromList(utf8.encode(caCertPem)),
      serverHost: serverHost,
      serverPort: serverPort,
      password: password,
    );
  }

  /// Load mTLS configuration from file paths.
  ///
  /// Useful for development/testing or when certificates are
  /// stored in the filesystem.
  static Future<MtlsConfig> fromFiles({
    required String clientCertPath,
    required String clientKeyPath,
    required String caCertPath,
    String? serverHost,
    int? serverPort,
    String? password,
  }) async {
    final clientCert = await File(clientCertPath).readAsBytes();
    final clientKey = await File(clientKeyPath).readAsBytes();
    final caCert = await File(caCertPath).readAsBytes();

    return MtlsConfig(
      clientCertificate: Uint8List.fromList(clientCert),
      clientPrivateKey: Uint8List.fromList(clientKey),
      caCertificate: Uint8List.fromList(caCert),
      serverHost: serverHost,
      serverPort: serverPort,
      password: password,
    );
  }

  /// Create a SecurityContext for TLS connections.
  ///
  /// The returned context can be used with [SecureSocket] or
  /// [WebSocket] connections.
  ///
  /// On mobile platforms, this configures:
  /// - Client certificate and key for authentication
  /// - CA certificate for server validation
  SecurityContext createSecurityContext() {
    final context = SecurityContext();

    // Set CA certificate to validate server
    context.setTrustedCertificatesBytes(caCertificate);

    // Set client certificate for authentication
    context.useCertificateChainBytes(clientCertificate);

    // Set client private key
    if (password != null) {
      context.usePrivateKeyBytes(clientPrivateKey, password: password);
    } else {
      context.usePrivateKeyBytes(clientPrivateKey);
    }

    return context;
  }

  /// Create an HttpClient configured for mTLS.
  ///
  /// The returned client can be used for HTTPS requests
  /// that require mutual TLS authentication.
  HttpClient createHttpClient() {
    // The SecurityContext pins the deployment CA, so Dart's default TLS
    // validation (chain + hostname/SAN) is exactly what we want. We must NOT
    // override badCertificateCallback to blanket-accept: that would defeat CA
    // pinning and allow a MITM to impersonate the server.
    return HttpClient(context: createSecurityContext());
  }

  /// Get the WebSocket URL for secure connection.
  ///
  /// Returns a wss:// URL using the configured host and port.
  String getWebSocketUrl({String path = '/ws'}) {
    if (serverHost == null || serverPort == null) {
      throw StateError('Server host and port must be configured');
    }
    return 'wss://$serverHost:$serverPort$path';
  }

  /// Validate that the configuration is complete.
  bool get isValid =>
      clientCertificate.isNotEmpty &&
      clientPrivateKey.isNotEmpty &&
      caCertificate.isNotEmpty;

  @override
  String toString() => 'MtlsConfig('
      'host: $serverHost, '
      'port: $serverPort, '
      'certSize: ${clientCertificate.length}, '
      'keySize: ${clientPrivateKey.length}, '
      'caSize: ${caCertificate.length}'
      ')';
}

/// Exception thrown when mTLS configuration fails.
class MtlsConfigException implements Exception {
  /// Creates an mTLS config exception.
  const MtlsConfigException(this.message, [this.cause]);

  /// Error message.
  final String message;

  /// Underlying cause, if any.
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'MtlsConfigException: $message (caused by: $cause)';
    }
    return 'MtlsConfigException: $message';
  }
}
