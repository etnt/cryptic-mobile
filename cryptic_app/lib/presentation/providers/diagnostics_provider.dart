/// Diagnostics data provider.
///
/// Aggregates certificate metadata, identity key summary, engine state,
/// and per-peer session diagnostics into a single snapshot for the UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/crypto_utils.dart';
import '../../data/storage/secure_storage/certificate_storage_service.dart';
import 'engine_provider.dart';

/// Read-only snapshot of all diagnostic data.
class DiagnosticsData {
  const DiagnosticsData({
    required this.certificate,
    required this.connection,
    required this.keys,
    required this.sessions,
    required this.app,
  });

  final CertificateDiag certificate;
  final ConnectionDiag connection;
  final KeysDiag keys;
  final Map<String, Map<String, dynamic>> sessions;
  final AppDiag app;
}

class CertificateDiag {
  const CertificateDiag({
    this.username,
    this.serverHost,
    this.serverPort,
    this.importedAt,
    this.expiresAt,
    this.fingerprint,
    this.isExpired = false,
    this.daysUntilExpiry,
  });

  final String? username;
  final String? serverHost;
  final int? serverPort;
  final DateTime? importedAt;
  final DateTime? expiresAt;
  final String? fingerprint;
  final bool isExpired;
  final int? daysUntilExpiry;
}

class ConnectionDiag {
  const ConnectionDiag({
    required this.engineStatus,
    required this.connectionStatus,
    this.wsUrl,
    this.lastConnectedAt,
    this.reconnectAttempts = 0,
    this.keysUploaded = false,
    this.onlineUserCount = 0,
  });

  final String engineStatus;
  final String connectionStatus;
  final String? wsUrl;
  final DateTime? lastConnectedAt;
  final int reconnectAttempts;
  final bool keysUploaded;
  final int onlineUserCount;
}

class KeysDiag {
  const KeysDiag({
    this.hasIdentityKeys = false,
    this.hasSignedPrekey = false,
    this.signedPrekeyId,
    this.oneTimePrekeyCount = 0,
    this.signingKeyFingerprint,
  });

  final bool hasIdentityKeys;
  final bool hasSignedPrekey;
  final int? signedPrekeyId;
  final int oneTimePrekeyCount;
  final String? signingKeyFingerprint;
}

class AppDiag {
  const AppDiag({
    required this.environment,
    required this.version,
    required this.logLevel,
    required this.serverHost,
    required this.serverPort,
  });

  final String environment;
  final String version;
  final String logLevel;
  final String serverHost;
  final int serverPort;
}

/// Provider that loads all diagnostics data.
final diagnosticsProvider = FutureProvider<DiagnosticsData>((ref) async {
  final certStorage = CertificateStorageService();
  final keyRepo = ref.read(keyRepositoryProvider);
  final engine = ref.read(engineProvider);
  final engineState = ref.read(currentEngineStateProvider);

  // Load certificate metadata
  final certMeta = await certStorage.loadMetadata();

  final certDiag = CertificateDiag(
    username: certMeta?.username,
    serverHost: certMeta?.serverHost,
    serverPort: certMeta?.serverPort,
    importedAt: certMeta?.importedAt,
    expiresAt: certMeta?.expiresAt,
    fingerprint: certMeta?.fingerprint,
    isExpired: certMeta?.isExpired ?? false,
    daysUntilExpiry: certMeta?.daysUntilExpiry,
  );

  // Load key summary and identity key fingerprint
  final keySummary = await keyRepo.getKeySummary();
  String? signingFingerprint;
  final identity = await keyRepo.loadIdentityKeys();
  if (identity != null) {
    final pubKey = identity.signPublicKey;
    if (pubKey.isNotEmpty) {
      signingFingerprint = CryptoUtils.formatKeyFingerprint(pubKey);
    }
  }

  final keysDiag = KeysDiag(
    hasIdentityKeys: keySummary['has_identity_keys'] as bool? ?? false,
    hasSignedPrekey: keySummary['has_signed_prekey'] as bool? ?? false,
    signedPrekeyId: keySummary['signed_prekey_id'] as int?,
    oneTimePrekeyCount: keySummary['one_time_prekey_count'] as int? ?? 0,
    signingKeyFingerprint: signingFingerprint,
  );

  // Connection diagnostics
  final config = AppConfig.current;
  final connectionDiag = ConnectionDiag(
    engineStatus: engineState.status.name,
    connectionStatus: engineState.connectionStatus.name,
    wsUrl: engineState.serverConfig?.wsUrl,
    lastConnectedAt: engineState.lastConnectedAt,
    reconnectAttempts: engineState.reconnectAttempts,
    keysUploaded: engineState.keysUploaded,
    onlineUserCount: engineState.users.length,
  );

  // Session diagnostics
  final sessionDiags = engine?.getAllSessionDiagnostics() ?? {};

  // App diagnostics
  final appDiag = AppDiag(
    environment: config.environment.name,
    version: '1.0.0+1',
    logLevel: config.logLevel.name,
    serverHost: config.serverHost,
    serverPort: config.serverPort,
  );

  return DiagnosticsData(
    certificate: certDiag,
    connection: connectionDiag,
    keys: keysDiag,
    sessions: sessionDiags,
    app: appDiag,
  );
});
