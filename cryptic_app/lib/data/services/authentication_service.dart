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
import '../storage/secure_storage/encrypted_secure_storage.dart';
import '../storage/secure_storage/key_storage_service.dart';
import 'passphrase_encryption_service.dart';

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

  /// Check if enrollment-issued certificates exist in secure storage.
  ///
  /// Unlike [hasCertificates], this ignores bundled dev assets and only
  /// returns true when the user has completed the enrollment flow.
  Future<bool> hasStoredCertificates() async {
    return _certificateStorage.hasCertificates();
  }

  /// Check if identity keys exist for a user.
  Future<bool> hasIdentityKeys() async => await _keyRepository.hasIdentityKeys();

  /// Authenticate and connect to the server.
  ///
  /// [username] - The username to authenticate as.
  /// [passphrase] - The passphrase for decrypting stored keys.
  /// [serverConfig] - Server connection configuration.
  Future<AuthenticationResult> authenticate({
    required String username,
    required String passphrase,
    required ServerConnectionConfig serverConfig,
  }) async {
    try {
      // If a passphrase has been set (post-enrollment), verify it and
      // create encrypted-aware storage so all reads/writes are
      // transparently encrypted.
      final encService = PassphraseEncryptionService();
      final passphraseSet = await encService.isPassphraseSet();

      KeyRepository keyRepository;
      SessionRepository sessionRepository;
      CertificateStorageService certificateStorage;

      if (passphraseSet) {
        final ok = await encService.verifyPassphrase(passphrase);
        if (!ok) {
          return AuthenticationResult.failure('Wrong passphrase');
        }

        // Build storage layer that decrypts sensitive keys on read
        // and re-encrypts on write.
        final encStorage = EncryptedSecureStorage(passphrase: passphrase);
        final keyStorageSvc = KeyStorageService(secureStorage: encStorage);
        certificateStorage = CertificateStorageService(secureStorage: encStorage);
        keyRepository = KeyRepository(keyStorage: keyStorageSvc);
        sessionRepository = SessionRepository(keyStorage: keyStorageSvc);
      } else {
        // No passphrase encryption — use plain storage (pre-enrollment
        // or development path).
        keyRepository = _keyRepository;
        sessionRepository = _sessionRepository;
        certificateStorage = _certificateStorage;
      }

      // Load mTLS configuration
      final mtlsConfig = await _loadMtlsConfig(
        serverConfig,
        certificateStorage: certificateStorage,
      );
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
        keyRepository: keyRepository,
        sessionRepository: sessionRepository,
        webSocketClient: webSocketClient,
      );

      // Initialize and connect
      await engine.initialize();
      await engine.connect();

      return AuthenticationResult.success(engine);
    } catch (e) {
      return AuthenticationResult.failure(_friendlyError(e));
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
  Future<MtlsConfig?> _loadMtlsConfig(
    ServerConnectionConfig config, {
    CertificateStorageService? certificateStorage,
  }) async {
    final certStorage = certificateStorage ?? _certificateStorage;

    // Try loading from secure storage first
    final storedConfig = await MtlsConfig.fromStorage(
      certificateStorage: certStorage,
      serverHost: config.host,
      serverPort: config.port,
    );

    if (storedConfig != null) {
      return storedConfig;
    }

    // Fall back to bundled certificates
    if (config.useBundledCerts) {
      return _loadBundledCertificates(config);
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

  /// Map raw error to a user-friendly message.
  static String _friendlyError(Object e) {
    final raw = e.toString();

    // TLS/certificate errors
    if (raw.contains('UNKNOWN_CA') || raw.contains('UNKOWN_CA')) {
      return 'Server does not trust your certificate.\n'
          'Please re-enroll against this server.';
    }
    if (raw.contains('CERTIFICATE_EXPIRED') ||
        raw.contains('certificate_expired')) {
      return 'Your client certificate has expired.\n'
          'Please re-enroll to obtain a new certificate.';
    }
    if (raw.contains('CERTIFICATE_REVOKED') ||
        raw.contains('certificate_revoked')) {
      return 'Your certificate has been revoked.\n'
          'Contact your administrator.';
    }
    if (raw.contains('HANDSHAKE_FAILURE') ||
        raw.contains('handshake_failure')) {
      return 'TLS handshake failed.\n'
          'The server may not support your TLS configuration.';
    }
    if (raw.contains('CERTIFICATE_UNKNOWN')) {
      return 'Server rejected your certificate.\n'
          'Please re-enroll against this server.';
    }
    if (raw.contains('BAD_CERTIFICATE')) {
      return 'Invalid client certificate.\n'
          'Please re-enroll to obtain a new certificate.';
    }

    // Network errors
    if (raw.contains('SocketException') ||
        raw.contains('Connection refused')) {
      return 'Cannot reach the server.\n'
          'Check the host and port, and your network connection.';
    }
    if (raw.contains('Connection timed out') ||
        raw.contains('timed out')) {
      return 'Connection timed out.\n'
          'Check your network connection and server address.';
    }
    if (raw.contains('No route to host') ||
        raw.contains('Network is unreachable')) {
      return 'Server is unreachable.\n'
          'Check your network connection.';
    }

    // DNS errors
    if (raw.contains('Failed host lookup') ||
        raw.contains('getaddrinfo')) {
      return 'Cannot resolve server hostname.\n'
          'Check the server address.';
    }

    // Passphrase / storage
    if (raw.contains('Wrong passphrase')) {
      return 'Wrong passphrase';
    }

    // Default: return the raw error
    return raw;
  }
}
