/// Enrollment flow screen.
///
/// Orchestrates the enrollment sub-screens:
/// 1. QR Scanner → 2. Passphrase Entry → 3. Progress/Result
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/enrollment_provider.dart';
import 'enrollment_progress_screen.dart';
import 'passphrase_screen.dart';
import 'qr_scanner_screen.dart';

/// Top-level enrollment flow screen.
///
/// Switches between sub-screens based on [EnrollmentPhase].
class EnrollmentFlowScreen extends ConsumerWidget {
  const EnrollmentFlowScreen({super.key, this.onComplete});

  /// Called when enrollment completes and user taps "Continue".
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(enrollmentProvider);

    return switch (status.phase) {
      EnrollmentPhase.scanQr => const QrScannerScreen(),
      EnrollmentPhase.enterPassphrase => const PassphraseScreen(),
      EnrollmentPhase.processing ||
      EnrollmentPhase.completed ||
      EnrollmentPhase.failed =>
        EnrollmentProgressScreen(onComplete: onComplete),
    };
  }
}
