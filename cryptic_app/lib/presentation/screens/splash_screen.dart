/// Splash screen.
///
/// Initial screen shown while loading the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';

/// Splash screen shown during app initialization.
class SplashScreen extends ConsumerStatefulWidget {
  /// Creates a splash screen.
  const SplashScreen({
    super.key,
    this.onInitialized,
  });

  /// Callback when initialization completes.
  final void Function(bool needsSetup)? onInitialized;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Simulate initialization delay
    await Future.delayed(const Duration(seconds: 1));

    // Check auth state
    await ref.read(authProvider.notifier).checkAuthState();

    if (mounted) {
      final authState = ref.read(authProvider);
      widget.onInitialized?.call(authState.needsSetup);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 100,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Cryptic',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'End-to-end encrypted messaging',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
