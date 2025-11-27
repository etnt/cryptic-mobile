// lib/data/crypto/keys/key_bundle.dart
//
// Complete key bundle for X3DH protocol.
//

import 'dart:convert';
import 'dart:typed_data';

import 'identity_key_pair.dart';
import 'one_time_prekey.dart';
import 'signed_prekey.dart';

/// A complete key bundle for X3DH initial key agreement.
///
/// The key bundle contains all the public keys needed to initiate
/// a secure session with another user without them being online.
///
/// Components:
/// - Identity keys (long-term, for authentication)
/// - Signed prekey (medium-term, rotated weekly)
/// - One-time prekey (optional, used once then deleted)
class KeyBundle {
  /// Creates a key bundle.
  const KeyBundle({
    required this.username,
    required this.identitySignKey,
    required this.identityDhKey,
    required this.signedPrekey,
    this.oneTimePrekey,
  });

  /// Username of the key bundle owner.
  final String username;

  /// Ed25519 public key for identity verification.
  final Uint8List identitySignKey;

  /// X25519 public key for identity DH.
  final Uint8List identityDhKey;

  /// Signed prekey with signature.
  final SignedPrekeyPublic signedPrekey;

  /// Optional one-time prekey (may be null if exhausted).
  final OneTimePrekeyPublic? oneTimePrekey;

  /// Whether this bundle includes a one-time prekey.
  bool get hasOneTimePrekey => oneTimePrekey != null;

  /// Converts to a map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'identity_sign_key': base64Encode(identitySignKey),
      'identity_dh_key': base64Encode(identityDhKey),
      'signed_prekey': signedPrekey.toMap(),
      if (oneTimePrekey != null) 'one_time_prekey': oneTimePrekey!.toMap(),
    };
  }

  /// Creates from a server response map.
  ///
  /// Handles the Cryptic server's response format.
  factory KeyBundle.fromServerResponse(Map<String, dynamic> map) {
    OneTimePrekeyPublic? otpk;
    if (map.containsKey('one_time_prekey') && map['one_time_prekey'] != null) {
      otpk = OneTimePrekeyPublic.fromMap(
        map['one_time_prekey'] as Map<String, dynamic>,
      );
    }

    return KeyBundle(
      username: map['username'] as String,
      identitySignKey: base64Decode(map['identity_sign_key'] as String),
      identityDhKey: base64Decode(map['identity_dh_key'] as String),
      signedPrekey: SignedPrekeyPublic.fromMap(
        map['signed_prekey'] as Map<String, dynamic>,
      ),
      oneTimePrekey: otpk,
    );
  }
}

/// User's own complete key material.
///
/// Contains both public and private components of all keys.
/// This is stored encrypted locally, never shared.
class OwnKeyBundle {
  /// Creates an own key bundle.
  const OwnKeyBundle({
    required this.identity,
    required this.signedPrekey,
    required this.oneTimePrekeys,
  });

  /// Long-term identity key pair.
  final IdentityKeyPair identity;

  /// Current signed prekey.
  final SignedPrekey signedPrekey;

  /// Pool of unused one-time prekeys.
  final Map<int, OneTimePrekey> oneTimePrekeys;

  /// Creates a key bundle for upload to server.
  KeyBundle toPublicBundle(String username) {
    return KeyBundle(
      username: username,
      identitySignKey: identity.signPublicKey,
      identityDhKey: identity.dhPublicKey,
      signedPrekey: signedPrekey.publicPart,
      oneTimePrekey: null, // One-time prekeys uploaded separately
    );
  }

  /// Gets a one-time prekey by ID and removes it from the pool.
  ///
  /// Returns null if the key ID is not found.
  OneTimePrekey? consumeOneTimePrekey(int keyId) {
    return oneTimePrekeys.remove(keyId);
  }

  /// How many one-time prekeys remain in the pool.
  int get remainingOneTimePrekeys => oneTimePrekeys.length;

  /// Whether we need to upload more one-time prekeys.
  bool get needsMoreOneTimePrekeys =>
      remainingOneTimePrekeys < OneTimePrekeyBatch.minimumPoolSize;

  /// Converts to a map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'identity': identity.toMap(),
      'signed_prekey': signedPrekey.toMap(),
      'one_time_prekeys': oneTimePrekeys.map(
        (id, pk) => MapEntry(id.toString(), pk.toMap()),
      ),
    };
  }

  /// Creates from a deserialized map.
  factory OwnKeyBundle.fromMap(Map<String, dynamic> map) {
    final otpkMap = map['one_time_prekeys'] as Map<String, dynamic>;
    final oneTimePrekeys = <int, OneTimePrekey>{};
    for (final entry in otpkMap.entries) {
      oneTimePrekeys[int.parse(entry.key)] = OneTimePrekey.fromMap(
        entry.value as Map<String, dynamic>,
      );
    }

    return OwnKeyBundle(
      identity: IdentityKeyPair.fromMap(
        map['identity'] as Map<String, dynamic>,
      ),
      signedPrekey: SignedPrekey.fromMap(
        map['signed_prekey'] as Map<String, dynamic>,
      ),
      oneTimePrekeys: oneTimePrekeys,
    );
  }
}
