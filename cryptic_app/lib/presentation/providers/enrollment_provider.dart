// lib/presentation/providers/enrollment_provider.dart
//
// State management for enrollment flow.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/enrollment/enrollment_service.dart';

/// Enrollment flow state.
enum EnrollmentPhase {
  /// Waiting for QR scan.
  scanQr,

  /// QR scanned, waiting for passphrase.
  enterPassphrase,

  /// Processing enrollment.
  processing,

  /// Enrollment completed successfully.
  completed,

  /// Enrollment failed.
  failed,
}

/// Enrollment status with progress and error info.
class EnrollmentStatus {
  const EnrollmentStatus({
    required this.phase,
    this.qrData,
    this.stage,
    this.error,
    this.result,
  });

  static const initial = EnrollmentStatus(phase: EnrollmentPhase.scanQr);

  final EnrollmentPhase phase;

  /// Raw QR data (set after scanning).
  final String? qrData;

  /// Current processing stage (when phase == processing).
  final EnrollmentStage? stage;

  /// Error message (when phase == failed).
  final String? error;

  /// Enrollment result (when phase == completed).
  final EnrollmentResult? result;

  bool get isProcessing => phase == EnrollmentPhase.processing;
  bool get isCompleted => phase == EnrollmentPhase.completed;
  bool get isFailed => phase == EnrollmentPhase.failed;

  EnrollmentStatus copyWith({
    EnrollmentPhase? phase,
    String? qrData,
    EnrollmentStage? stage,
    String? error,
    EnrollmentResult? result,
    bool clearError = false,
  }) => EnrollmentStatus(
      phase: phase ?? this.phase,
      qrData: qrData ?? this.qrData,
      stage: stage ?? this.stage,
      error: clearError ? null : (error ?? this.error),
      result: result ?? this.result,
    );
}

/// Notifier for enrollment flow.
class EnrollmentNotifier extends StateNotifier<EnrollmentStatus> {
  EnrollmentNotifier({
    EnrollmentService? enrollmentService,
  })  : _enrollmentService = enrollmentService ?? EnrollmentService(),
        super(EnrollmentStatus.initial);

  final EnrollmentService _enrollmentService;

  /// Called when a QR code is scanned.
  void onQrScanned(String qrData) {
    state = state.copyWith(
      phase: EnrollmentPhase.enterPassphrase,
      qrData: qrData,
    );
  }

  /// Execute enrollment with the scanned QR data and passphrase.
  Future<bool> enroll(String passphrase) async {
    final qrData = state.qrData;
    if (qrData == null) {
      state = state.copyWith(
        phase: EnrollmentPhase.failed,
        error: 'No QR data — please scan again',
      );
      return false;
    }

    state = state.copyWith(
      phase: EnrollmentPhase.processing,
      clearError: true,
    );

    try {
      final result = await _enrollmentService.enroll(
        qrData: qrData,
        passphrase: passphrase,
        onProgress: (stage) {
          state = state.copyWith(stage: stage);
        },
      );

      state = state.copyWith(
        phase: EnrollmentPhase.completed,
        result: result,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        phase: EnrollmentPhase.failed,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Reset to scan a new QR code.
  void reset() {
    state = EnrollmentStatus.initial;
  }

  /// Go back from passphrase entry to QR scanning.
  void backToScan() {
    state = EnrollmentStatus.initial;
  }
}

/// Provider for enrollment state.
final enrollmentProvider =
    StateNotifierProvider<EnrollmentNotifier, EnrollmentStatus>(
  (ref) => EnrollmentNotifier(),
);
