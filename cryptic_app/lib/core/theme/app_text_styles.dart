/// App text styles.
///
/// Defines consistent typography for the Cryptic app.
library;

import 'package:flutter/material.dart';

/// App text styles.
abstract final class AppTextStyles {
  // ─────────────────────────────────────────────────────────────────────────
  // Headings
  // ─────────────────────────────────────────────────────────────────────────

  /// Large headline.
  static const headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  /// Medium headline.
  static const headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.25,
  );

  /// Small headline.
  static const headlineSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Titles
  // ─────────────────────────────────────────────────────────────────────────

  /// Large title.
  static const titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );

  /// Medium title.
  static const titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.15,
  );

  /// Small title.
  static const titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Body Text
  // ─────────────────────────────────────────────────────────────────────────

  /// Large body text.
  static const bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    letterSpacing: 0.5,
  );

  /// Medium body text.
  static const bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    letterSpacing: 0.25,
  );

  /// Small body text.
  static const bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    letterSpacing: 0.4,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Labels
  // ─────────────────────────────────────────────────────────────────────────

  /// Large label.
  static const labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// Medium label.
  static const labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  /// Small label.
  static const labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Chat-specific
  // ─────────────────────────────────────────────────────────────────────────

  /// Message text in chat bubbles.
  static const messageText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.4,
  );

  /// Timestamp text.
  static const timestamp = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.normal,
    letterSpacing: 0.2,
  );

  /// Username/sender text.
  static const senderName = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// System message text.
  static const systemMessage = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    fontStyle: FontStyle.italic,
  );
}
