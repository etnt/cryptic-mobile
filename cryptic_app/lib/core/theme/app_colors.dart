/// App color definitions.
///
/// Defines the color palette for the Cryptic app.
library;

import 'package:flutter/material.dart';

/// App color palette.
abstract final class AppColors {
  // ─────────────────────────────────────────────────────────────────────────
  // Primary Colors
  // ─────────────────────────────────────────────────────────────────────────

  /// Primary brand color - a secure blue.
  static const primary = Color(0xFF2196F3);

  /// Primary color variant.
  static const primaryVariant = Color(0xFF1976D2);

  /// Secondary accent color.
  static const secondary = Color(0xFF4CAF50);

  /// Secondary color variant.
  static const secondaryVariant = Color(0xFF388E3C);

  // ─────────────────────────────────────────────────────────────────────────
  // Surface Colors - Light Theme
  // ─────────────────────────────────────────────────────────────────────────

  /// Light theme background.
  static const backgroundLight = Color(0xFFF5F5F5);

  /// Light theme surface.
  static const surfaceLight = Color(0xFFFFFFFF);

  /// Light theme card.
  static const cardLight = Color(0xFFFFFFFF);

  // ─────────────────────────────────────────────────────────────────────────
  // Surface Colors - Dark Theme
  // ─────────────────────────────────────────────────────────────────────────

  /// Dark theme background.
  static const backgroundDark = Color(0xFF121212);

  /// Dark theme surface.
  static const surfaceDark = Color(0xFF1E1E1E);

  /// Dark theme card.
  static const cardDark = Color(0xFF2C2C2C);

  // ─────────────────────────────────────────────────────────────────────────
  // Text Colors
  // ─────────────────────────────────────────────────────────────────────────

  /// Primary text on light background.
  static const textPrimaryLight = Color(0xFF212121);

  /// Secondary text on light background.
  static const textSecondaryLight = Color(0xFF757575);

  /// Primary text on dark background.
  static const textPrimaryDark = Color(0xFFFFFFFF);

  /// Secondary text on dark background.
  static const textSecondaryDark = Color(0xFFB0B0B0);

  // ─────────────────────────────────────────────────────────────────────────
  // Message Bubble Colors
  // ─────────────────────────────────────────────────────────────────────────

  /// Outgoing message bubble - light theme.
  static const bubbleOutgoingLight = Color(0xFFE3F2FD);

  /// Incoming message bubble - light theme.
  static const bubbleIncomingLight = Color(0xFFFFFFFF);

  /// Outgoing message bubble - dark theme.
  static const bubbleOutgoingDark = Color(0xFF1565C0);

  /// Incoming message bubble - dark theme.
  static const bubbleIncomingDark = Color(0xFF2C2C2C);

  // ─────────────────────────────────────────────────────────────────────────
  // Status Colors
  // ─────────────────────────────────────────────────────────────────────────

  /// Success/online color.
  static const success = Color(0xFF4CAF50);

  /// Warning color.
  static const warning = Color(0xFFFF9800);

  /// Error/offline color.
  static const error = Color(0xFFF44336);

  /// Info color.
  static const info = Color(0xFF2196F3);

  /// Encryption indicator color.
  static const encrypted = Color(0xFF4CAF50);

  // ─────────────────────────────────────────────────────────────────────────
  // Connection Status Colors
  // ─────────────────────────────────────────────────────────────────────────

  /// Connected status color.
  static const connected = Color(0xFF4CAF50);

  /// Connecting status color.
  static const connecting = Color(0xFFFF9800);

  /// Disconnected status color.
  static const disconnected = Color(0xFF9E9E9E);

  /// Connection error color.
  static const connectionError = Color(0xFFF44336);
}
