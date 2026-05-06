/// Set-passphrase screen shown after enrollment completes.
///
/// The user chooses their own passphrase which will be used to encrypt
/// all stored key material (identity keys, prekeys, sessions, certs).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/passphrase_encryption_service.dart';
import '../../providers/enrollment_provider.dart';

/// Screen for setting a new passphrase after enrollment.
class SetPassphraseScreen extends ConsumerStatefulWidget {
  const SetPassphraseScreen({required this.onComplete, super.key});

  /// Called after the passphrase has been set and keys encrypted.
  final VoidCallback onComplete;

  @override
  ConsumerState<SetPassphraseScreen> createState() =>
      _SetPassphraseScreenState();
}

class _SetPassphraseScreenState extends ConsumerState<SetPassphraseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final passphrase = _passphraseController.text;

      // 1. Set passphrase verifier
      final encService = PassphraseEncryptionService();
      await encService.setPassphrase(passphrase);

      // 2. Encrypt all stored key material with the new passphrase
      await ref
          .read(enrollmentProvider.notifier)
          .encryptStoredKeys(passphrase);

      if (mounted) {
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to set passphrase: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.enhanced_encryption,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Set Your Passphrase',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a personal passphrase to protect your '
                    'encryption keys. You will need it every time '
                    'you log in.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),

                  // New passphrase
                  TextFormField(
                    controller: _passphraseController,
                    obscureText: _obscure,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'New Passphrase',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a passphrase';
                      }
                      if (value.length < 6) {
                        return 'Passphrase must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm passphrase
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm Passphrase',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value != _passphraseController.text) {
                        return 'Passphrases do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),  
                          )
                        : const Icon(Icons.check),
                    label: Text(
                        _saving ? 'Encrypting keys...' : 'Set Passphrase',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
