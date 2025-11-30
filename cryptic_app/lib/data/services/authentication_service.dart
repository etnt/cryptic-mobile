// lib/data/services/authentication_service.dart
//
// Authentication Service - Handles mTLS certificate loading and engine setup
//

import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../engine/cryptic_engine.dart';
import '../engine/engine_state.dart';
import '../network/websocket/mtls_config.dart';
import '../network/websocket/websocket_client.dart';
import '../storage/repositories/key_repository.dart';
import '../storage/repositories/session_repository.dart';
import '../storage/secure_storage/certificate_storage_service.dart';

/// Result of authentication attempt.
class AuthenticationResult {
  /// Creates an authentication result.
  const AuthenticationResult({
    required this.success,
    this.engine,
    this.error,
  });

  /// Successful authentication.
  factory AuthenticationResult.success(CrypticEngine engine) =>
      AuthenticationResult(success: true, engine: engine);

  /// Failed authentication.
  factory AuthenticationResult.failure(String error) =>
      AuthenticationResult(success: false, error: error);

  /// Whether authentication succeeded.
  final bool success;

  /// The initialized engine (if successful).
  final CrypticEngine? engine;

  /// Error message (if failed).
  final String? error;
}

/// Server configuration for connection.
class ServerConnectionConfig {
  /// Creates a server connection config.
  const ServerConnectionConfig({
    required this.host,
    required this.port,
    this.useBundledCerts = true,
  });

  /// Default localhost configuration for development.
  static const localhost = ServerConnectionConfig(
    host: 'localhost',
    port: 8443,
    useBundledCerts: true,
  );

  /// Server hostname.
  final String host;

  /// Server port.
  final int port;

  /// Whether to use bundled certificates from assets.
  final bool useBundledCerts;
}

/// Service for handling authentication and engine setup.
///
/// Responsibilities:
/// - Loading mTLS certificates (from assets or secure storage)
/// - Creating WebSocket client with mTLS
/// - Initializing and connecting the CrypticEngine
class AuthenticationService {
  /// Creates an authentication service.
  AuthenticationService({
    CertificateStorageService? certificateStorage,
    KeyRepository? keyRepository,
    SessionRepository? sessionRepository,
  })  : _certificateStorage =
            certificateStorage ?? CertificateStorageService(),
        _keyRepository = keyRepository ?? KeyRepository(),
        _sessionRepository = sessionRepository ?? SessionRepository();

  final CertificateStorageService _certificateStorage;
  final KeyRepository _keyRepository;
  final SessionRepository _sessionRepository;

  /// Check if certificates are available (either bundled or stored).
  Future<bool> hasCertificates() async {
    // Check secure storage first
    if (await _certificateStorage.hasCertificates()) {
      return true;
    }

    // Check if bundled certificates exist
    try {
      await rootBundle.load('assets/certificates/client.crt');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Check if identity keys exist for a user.
  Future<bool> hasIdentityKeys() async {
    return await _keyRepository.hasIdentityKeys();
  }

  /// Authenticate and connect to the server.
  ///
  /// [username] - The username to authenticate as.
  /// [passphrase] - The passphrase (for future key encryption).
  /// [serverConfig] - Server connection configuration.
  Future<AuthenticationResult> authenticate({
    required String username,
    required String passphrase,
    required ServerConnectionConfig serverConfig,
  }) async {
    try {
      // Load mTLS configuration
      final mtlsConfig = await _loadMtlsConfig(serverConfig);
      if (mtlsConfig == null) {
        return AuthenticationResult.failure(
          'No certificates available. Please import certificates first.',
        );
      }

      // Create WebSocket client
      final webSocketClient = WebSocketClient(mtlsConfig: mtlsConfig);

      // Create engine
      final engine = CrypticEngine(
        username: username,
        serverConfig: ServerConfig(
          host: serverConfig.host,
          port: serverConfig.port,
        ),
        keyRepository: _keyRepository,
        sessionRepository: _sessionRepository,
        webSocketClient: webSocketClient,
      );

      // Initialize and connect
      await engine.initialize();
      await engine.connect();

      return AuthenticationResult.success(engine);
    } catch (e) {
      return AuthenticationResult.failure(e.toString());
    }
  }

  /// Set up a new user with generated keys.
  ///
  /// [username] - The username to set up.
  /// [passphrase] - The passphrase for key encryption.
  /// [serverConfig] - Server connection configuration.
  Future<AuthenticationResult> setup({
    required String username,
    required String passphrase,
    required ServerConnectionConfig serverConfig,
  }) async {
    try {
      // For setup, we also authenticate (keys are generated during initialize)
      return await authenticate(
        username: username,
        passphrase: passphrase,
        serverConfig: serverConfig,
      );
    } catch (e) {
      return AuthenticationResult.failure(e.toString());
    }
  }

  /// Load mTLS configuration from available sources.
  Future<MtlsConfig?> _loadMtlsConfig(ServerConnectionConfig config) async {
    // Try loading from secure storage first
    final storedConfig = await MtlsConfig.fromStorage(
      certificateStorage: _certificateStorage,
      serverHost: config.host,
      serverPort: config.port,
    );

    if (storedConfig != null) {
      return storedConfig;
    }

    // Fall back to bundled certificates
    if (config.useBundledCerts) {
      return await _loadBundledCertificates(config);
    }

    return null;
  }

  /// Load certificates from bundled assets.
  Future<MtlsConfig?> _loadBundledCertificates(
    ServerConnectionConfig config,
  ) async {
    try {
      final clientCert = await rootBundle.load('assets/certificates/client.crt');
      final clientKey = await rootBundle.load('assets/certificates/client.key');
      final caCert = await rootBundle.load('assets/certificates/ca.crt');

      return MtlsConfig(
        clientCertificate: Uint8List.view(clientCert.buffer),
        clientPrivateKey: Uint8List.view(clientKey.buffer),
        caCertificate: Uint8List.view(caCert.buffer),
        serverHost: config.host,
        serverPort: config.port,
      );
    } catch (e) {
      // Certificates not bundled or failed to load
      return null;
    }
  }

  /// Import certificates from PEM strings.
  Future<void> importCertificates({
    required String clientCertPem,
    required String clientKeyPem,
    required String caCertPem,
    required String username,
    required String serverHost,
    required int serverPort,
  }) async {
    final metadata = CertificateMetadata(
      username: username,
      serverHost: serverHost,
      serverPort: serverPort,
      importedAt: DateTime.now(),
    );

    await _certificateStorage.storeCertificates(
      clientCertPem: clientCertPem,
      clientKeyPem: clientKeyPem,
      caCertPem: caCertPem,
      metadata: metadata,
    );
  }

  /// Store bundled certificates to secure storage for persistence.
  Future<void> persistBundledCertificates({
    required String username,
    required String serverHost,
    required int serverPort,
  }) async {
    final clientCert = await rootBundle.loadString('assets/certificates/client.crt');
    final clientKey = await rootBundle.loadString('assets/certificates/client.key');
    final caCert = await rootBundle.loadString('assets/certificates/ca.crt');

    await importCertificates(
      clientCertPem: clientCert,
      clientKeyPem: clientKey,
      caCertPem: caCert,
      username: username,
      serverHost: serverHost,
      serverPort: serverPort,
    );
  }
}
