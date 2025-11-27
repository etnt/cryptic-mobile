// lib/core/config/app_config.dart
//
// Application configuration for different environments
//

/// Supported application environments.
enum Environment {
  /// Local development environment
  development,

  /// Staging/testing environment
  staging,

  /// Production environment
  production,
}

/// Application configuration holder.
///
/// Provides environment-specific settings for server URLs,
/// logging, and other runtime configuration.
class AppConfig {
  /// Creates a new configuration instance.
  const AppConfig._({
    required this.environment,
    required this.serverHost,
    required this.serverPort,
    required this.useTls,
    required this.logLevel,
    required this.enableConsoleLogging,
    required this.connectionTimeoutSeconds,
    required this.reconnectDelaySeconds,
    required this.maxReconnectAttempts,
    required this.oneTimePrekeysToMaintain,
  });

  /// Development configuration (localhost).
  static const AppConfig development = AppConfig._(
    environment: Environment.development,
    serverHost: 'localhost',
    serverPort: 8443,
    useTls: true,
    logLevel: LogLevel.debug,
    enableConsoleLogging: true,
    connectionTimeoutSeconds: 10,
    reconnectDelaySeconds: 2,
    maxReconnectAttempts: 10,
    oneTimePrekeysToMaintain: 10,
  );

  /// Staging configuration.
  static const AppConfig staging = AppConfig._(
    environment: Environment.staging,
    serverHost: 'staging.cryptic.example.com',
    serverPort: 443,
    useTls: true,
    logLevel: LogLevel.info,
    enableConsoleLogging: true,
    connectionTimeoutSeconds: 15,
    reconnectDelaySeconds: 3,
    maxReconnectAttempts: 5,
    oneTimePrekeysToMaintain: 20,
  );

  /// Production configuration.
  static const AppConfig production = AppConfig._(
    environment: Environment.production,
    serverHost: 'cryptic.example.com',
    serverPort: 443,
    useTls: true,
    logLevel: LogLevel.warning,
    enableConsoleLogging: false,
    connectionTimeoutSeconds: 20,
    reconnectDelaySeconds: 5,
    maxReconnectAttempts: 3,
    oneTimePrekeysToMaintain: 50,
  );

  /// Current active configuration.
  ///
  /// This is set based on build flavor or compile-time constant.
  /// Override this for testing or environment switching.
  static AppConfig current = development;

  /// The current environment.
  final Environment environment;

  /// Cryptic server hostname.
  final String serverHost;

  /// Cryptic server port.
  final int serverPort;

  /// Whether to use TLS/mTLS for connections.
  final bool useTls;

  /// Minimum log level to output.
  final LogLevel logLevel;

  /// Whether to output logs to console/debug.
  final bool enableConsoleLogging;

  /// WebSocket connection timeout in seconds.
  final int connectionTimeoutSeconds;

  /// Delay between reconnection attempts in seconds.
  final int reconnectDelaySeconds;

  /// Maximum number of reconnection attempts before giving up.
  final int maxReconnectAttempts;

  /// Number of one-time prekeys to maintain on server.
  ///
  /// New keys are uploaded when count drops below half this value.
  final int oneTimePrekeysToMaintain;

  /// WebSocket URL for the Cryptic server.
  String get websocketUrl {
    final protocol = useTls ? 'wss' : 'ws';
    return '$protocol://$serverHost:$serverPort/ws';
  }

  /// Whether this is a development environment.
  bool get isDevelopment => environment == Environment.development;

  /// Whether this is a production environment.
  bool get isProduction => environment == Environment.production;

  @override
  String toString() => 'AppConfig(${environment.name}, $serverHost:$serverPort)';
}

/// Log levels for filtering output.
enum LogLevel {
  /// All messages including verbose debugging.
  debug,

  /// Informational messages.
  info,

  /// Warning messages.
  warning,

  /// Error messages only.
  error,

  /// No logging.
  none,
}
