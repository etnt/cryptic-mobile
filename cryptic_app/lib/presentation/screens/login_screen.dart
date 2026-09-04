/// Login screen.
///
/// Handles user authentication with username, passphrase, and server config.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage/secure_storage/certificate_storage_service.dart';
import '../../data/storage/secure_storage/secure_storage_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_overlay.dart';

/// Storage key for user-chosen server configuration.
const _kServerConfigKey = 'cryptic_user_server_config';

/// Login screen for user authentication.
class LoginScreen extends ConsumerStatefulWidget {
  /// Creates a login screen.
  const LoginScreen({
    super.key,
    this.onLoginSuccess,
    this.onReenroll,
  });

  /// Callback when login succeeds.
  final VoidCallback? onLoginSuccess;

  /// Callback when user wants to re-enroll.
  final VoidCallback? onReenroll;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _serverHostController = TextEditingController(text: 'localhost');
  final _serverPortController = TextEditingController(text: '8443');
  bool _obscurePassphrase = true;
  bool _isNewUser = false;
  bool _showServerConfig = false;
  bool _isLoadingConfig = true;

  @override
  void initState() {
    super.initState();
    _loadStoredConfig();
  }

  Future<void> _loadStoredConfig() async {
    try {
      final storage = SecureStorageService();

      // 1. Load user's previously chosen server config (saved on successful login)
      final savedConfig = await storage.readJson(key: _kServerConfigKey);
      if (savedConfig != null && mounted) {
        _usernameController.text = savedConfig['username'] as String? ?? '';
        _serverHostController.text =
            savedConfig['host'] as String? ?? 'localhost';
        _serverPortController.text =
            (savedConfig['port'] as int? ?? 8443).toString();
        _showServerConfig = true;
      } else {
        // 2. Fall back to enrollment metadata for first login after enrollment
        final certStorage = CertificateStorageService();
        final metadata = await certStorage.loadMetadata();
        if (metadata != null && mounted) {
          _usernameController.text = metadata.username;
          // Don't use the enrollment host — it may be an internal address.
          // Only use it if it looks like a real hostname (not localhost/10.0.2.2).
          final host = metadata.serverHost;
          if (host != 'localhost' &&
              host != '127.0.0.1' &&
              host != '10.0.2.2') {
            _serverHostController.text = host;
            _serverPortController.text = metadata.serverPort.toString();
          }
          _showServerConfig = true;
        }
      }
    } catch (_) {
      // Ignore — use defaults
    }
    if (mounted) {
      setState(() {
        _isLoadingConfig = false;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passphraseController.dispose();
    _serverHostController.dispose();
    _serverPortController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authNotifier = ref.read(authProvider.notifier);
    final username = _usernameController.text.trim();
    final serverHost = _serverHostController.text.trim();
    final serverPort = int.tryParse(_serverPortController.text.trim()) ?? 8443;

    debugPrint('[LoginScreen] Connecting to $serverHost:$serverPort');

    final success = _isNewUser
        ? await authNotifier.setup(
            username: username,
            passphrase: _passphraseController.text,
            serverHost: serverHost,
            serverPort: serverPort,
          )
        : await authNotifier.authenticate(
            username: username,
            passphrase: _passphraseController.text,
            serverHost: serverHost,
            serverPort: serverPort,
          );

    if (success && mounted) {
      // Persist the user's server choice for next login
      try {
        final storage = SecureStorageService();
        await storage.writeJson(key: _kServerConfigKey, value: {
          'username': username,
          'host': serverHost,
          'port': serverPort,
        });
      } catch (_) {
        // Non-critical, ignore
      }
      widget.onLoginSuccess?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: _isLoadingConfig
          ? const Center(child: CircularProgressIndicator())
          : LoadingOverlay(
              isLoading: authState.isAuthenticating,
              message:
                  _isNewUser ? 'Connecting & setting up...' : 'Connecting...',
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Logo/Icon
                          Icon(
                            Icons.lock_outline,
                            size: 80,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 24),

                          // Title
                          Text(
                            'Cryptic',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isNewUser
                                ? 'Create your account'
                                : 'End-to-end encrypted messaging',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 48),

                          // Error message
                          if (authState.error != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                authState.error!,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),

                          // Username field
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter a username';
                              }
                              if (value.trim().length < 3) {
                                return 'Username must be at least 3 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Passphrase field
                          TextFormField(
                            controller: _passphraseController,
                            decoration: InputDecoration(
                              labelText: 'Passphrase',
                              prefixIcon: const Icon(Icons.key_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassphrase
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassphrase = !_obscurePassphrase;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscurePassphrase,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a passphrase';
                              }
                              if (_isNewUser && value.length < 6) {
                                return 'Passphrase must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Server configuration toggle
                          InkWell(
                            onTap: () {
                              setState(() {
                                _showServerConfig = !_showServerConfig;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _showServerConfig
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Server Configuration',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Server config fields (collapsible)
                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 200),
                            crossFadeState: _showServerConfig
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            firstChild: Column(
                              children: [
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _serverHostController,
                                        decoration: const InputDecoration(
                                          labelText: 'Server Host',
                                          prefixIcon: Icon(Icons.dns_outlined),
                                          hintText: 'localhost',
                                        ),
                                        textInputAction: TextInputAction.next,
                                        validator: (value) {
                                          if (value == null ||
                                              value.trim().isEmpty) {
                                            return 'Required';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _serverPortController,
                                        decoration: const InputDecoration(
                                          labelText: 'Port',
                                          hintText: '8443',
                                        ),
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) => _submit(),
                                        validator: (value) {
                                          if (value == null ||
                                              value.trim().isEmpty) {
                                            return 'Required';
                                          }
                                          final port =
                                              int.tryParse(value.trim());
                                          if (port == null ||
                                              port < 1 ||
                                              port > 65535) {
                                            return 'Invalid';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Using bundled certificates',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            secondChild: const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 24),

                          // Submit button
                          FilledButton(
                            onPressed:
                                authState.isAuthenticating ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                _isNewUser ? 'Create & Connect' : 'Connect',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Toggle new user
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isNewUser = !_isNewUser;
                              });
                            },
                            child: Text(
                              _isNewUser
                                  ? 'Already have an account? Sign in'
                                  : 'New user? Create account',
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Re-enroll
                          if (widget.onReenroll != null)
                            TextButton.icon(
                              onPressed: widget.onReenroll,
                              icon: const Icon(Icons.qr_code, size: 18),
                              label: const Text('Re-enroll with QR code'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
