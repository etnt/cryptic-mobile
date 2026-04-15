/// Enrollment progress and completion screen.
///
/// Shows step-by-step progress during enrollment, then a success message.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/enrollment/enrollment_service.dart';
import '../../providers/enrollment_provider.dart';

/// Screen showing enrollment progress and final result.
class EnrollmentProgressScreen extends ConsumerWidget {
  const EnrollmentProgressScreen({super.key, this.onComplete});

  /// Called when the user taps "Continue" after enrollment completes.
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(enrollmentProvider);

    if (status.isCompleted) {
      return _buildSuccess(context, theme, status.result!);
    }

    if (status.isFailed) {
      return _buildFailure(context, theme, ref, status.error ?? 'Unknown error');
    }

    return _buildProgress(context, theme, status.stage);
  }

  Widget _buildProgress(
    BuildContext context,
    ThemeData theme,
    EnrollmentStage? stage,
  ) => Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 32),
                Text(
                  'Setting up your device...',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  _stageLabel(stage),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 48),
                _buildStepList(theme, stage),
              ],
            ),
          ),
        ),
      ),
    );

  Widget _buildStepList(ThemeData theme, EnrollmentStage? currentStage) {
    const stages = EnrollmentStage.values;
    final currentIndex =
        currentStage != null ? stages.indexOf(currentStage) : -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: stages.map((stage) {
        final stageIndex = stages.indexOf(stage);
        final isDone = stageIndex < currentIndex;
        final isCurrent = stageIndex == currentIndex;

        IconData icon;
        Color color;
        if (isDone) {
          icon = Icons.check_circle;
          color = theme.colorScheme.primary;
        } else if (isCurrent) {
          icon = Icons.radio_button_checked;
          color = theme.colorScheme.primary;
        } else {
          icon = Icons.radio_button_unchecked;
          color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _stageLabel(stage),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDone || isCurrent
                        ? theme.colorScheme.onSurface
                        : color,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSuccess(
    BuildContext context,
    ThemeData theme,
    EnrollmentResult result,
  ) => Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Enrollment Complete!',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome, ${result.username}',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connected to ${result.serverHost}:${result.serverPort}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 48),
                FilledButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continue to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

  Widget _buildFailure(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    String error,
  ) => Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 80,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 24),
                Text(
                  'Enrollment Failed',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(enrollmentProvider.notifier).reset();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

  String _stageLabel(EnrollmentStage? stage) => switch (stage) {
      EnrollmentStage.parsingQr => 'Parsing QR code...',
      EnrollmentStage.decrypting => 'Decrypting enrollment data...',
      EnrollmentStage.verifyingCa => 'Verifying CA certificate...',
      EnrollmentStage.generatingCsr => 'Generating TLS keys...',
      EnrollmentStage.signingCsr => 'Signing certificate request...',
      EnrollmentStage.submittingCsr => 'Submitting to server...',
      EnrollmentStage.storingCertificate => 'Storing certificate...',
      EnrollmentStage.complete => 'Complete!',
      null => 'Preparing...',
    };
}
