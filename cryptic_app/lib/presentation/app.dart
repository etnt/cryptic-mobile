// lib/presentation/app.dart
//
// Root application widget
//

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/logger.dart';

/// Root application widget.
///
/// Sets up the MaterialApp with theming, routing, and global configuration.
class CrypticApp extends ConsumerWidget {
  /// Creates the root application widget.
  const CrypticApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppLogger.debug('Building CrypticApp', tag: 'App');

    return MaterialApp(
      title: 'Cryptic',
      debugShowCheckedModeBanner: false,

      // Theme configuration
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3), // Blue primary
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        // Card styling for message bubbles
        cardTheme: const CardTheme(
          elevation: 1,
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        // Input styling
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),

      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: const CardTheme(
          elevation: 1,
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),

      themeMode: ThemeMode.system,

      // TODO(M7): Replace with proper routing using go_router or similar
      home: const _PlaceholderScreen(),
    );
  }
}

/// Placeholder screen shown until proper screens are implemented.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cryptic'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Cryptic Mobile',
                style: theme.textTheme.headlineMedium?.copyWith(
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
              const _MilestoneProgress(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows implementation progress for development.
class _MilestoneProgress extends StatelessWidget {
  const _MilestoneProgress();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Implementation Progress',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildMilestone('M1: Project Bootstrap', true),
            _buildMilestone('M2: Crypto Primitives', false),
            _buildMilestone('M3: Secure Storage', false),
            _buildMilestone('M4: X3DH Key Agreement', false),
            _buildMilestone('M5: Double Ratchet', false),
            _buildMilestone('M6: WebSocket mTLS', false),
            _buildMilestone('M7: Chat UI', false),
            _buildMilestone('M8: Polish & Testing', false),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestone(String name, bool completed) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              completed ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: completed ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                decoration: completed ? TextDecoration.lineThrough : null,
                color: completed ? Colors.grey : null,
              ),
            ),
          ],
        ),
      );
}
