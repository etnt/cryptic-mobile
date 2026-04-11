/// Passphrase entry screen for enrollment.
///
/// Prompts the user for the passphrase they received from the admin.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/enrollment_provider.dart';

/// Screen for entering the enrollment passphrase.
class PassphraseScreen extends ConsumerStatefulWidget {
  const PassphraseScreen({super.key});

  @override
  ConsumerState<PassphraseScreen> createState() => _PassphraseScreenState();
}

class _PassphraseScreenState extends ConsumerState<PassphraseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(enrollmentProvider.notifier).enroll(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(enrollmentProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Passphrase'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(enrollmentProvider.notifier).backToScan();
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.qr_code_2,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'QR Code Scanned',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the passphrase your administrator '
                    'provided to complete enrollment.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _controller,
                    obscureText: _obscure,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Passphrase',
                      prefixIcon: const Icon(Icons.key),
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
                        return 'Please enter the passphrase';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (status.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      status.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: status.isProcessing ? null : _submit,
                    icon: status.isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      status.isProcessing ? 'Enrolling...' : 'Enroll',
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
