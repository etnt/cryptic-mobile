// lib/core/utils/crypto_utils.dart
//
// Cryptographic display utilities for the UI layer.

import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// Utilities for formatting cryptographic data for display.
abstract class CryptoUtils {
  /// Computes the SHA-256 fingerprint of a public key and formats it
  /// as uppercase hex grouped in 4-character blocks.
  ///
  /// Example output: `F479 A1EB AAAD FFF4 3B2C 91DE`
  ///
  /// [maxGroups] limits how many 4-char groups to show (default 6 = 24 hex chars).
  static String formatKeyFingerprint(Uint8List publicKey, {int maxGroups = 6}) {
    final digest = SHA256Digest();
    final hash = Uint8List(digest.digestSize);
    digest.update(publicKey, 0, publicKey.length);
    digest.doFinal(hash, 0);

    final hex = _bytesToHex(hash).toUpperCase();

    final groups = <String>[];
    for (var i = 0; i < hex.length && groups.length < maxGroups; i += 4) {
      final end = (i + 4).clamp(0, hex.length);
      groups.add(hex.substring(i, end));
    }
    return groups.join(' ');
  }

  /// Formats a full SHA-256 fingerprint with no truncation.
  static String fullFingerprint(Uint8List publicKey) =>
      formatKeyFingerprint(publicKey, maxGroups: 16);

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
