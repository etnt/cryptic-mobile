// lib/data/crypto/keys/key_generator.dart
//
// Key generation service for all cryptographic keys.
//

import 'dart:typed_data';

import '../primitives/ed25519_service.dart';
import '../primitives/x25519_service.dart';
import 'identity_key_pair.dart';
import 'one_time_prekey.dart';
import 'signed_prekey.dart';
import 'key_bundle.dart';

/// Service for generating cryptographic keys.
///
/// Generates all key types needed for X3DH and Double Ratchet:
/// - Identity key pairs (Ed25519 + X25519)
/// - Signed prekeys (X25519 + signature)
/// - One-time prekeys (X25519)
class KeyGenerator {
  /// Creates a key generator with the required crypto services.
  KeyGenerator({
    Ed25519Service? ed25519,
    X25519Service? x25519,
  })  : _ed25519 = ed25519 ?? Ed25519Service(),
        _x25519 = x25519 ?? X25519Service();

  final Ed25519Service _ed25519;
  final X25519Service _x25519;

  /// Counter for generating unique key IDs.
  int _nextKeyId = 1;

  /// Sets the next key ID to use (for persistence).
  set nextKeyId(int value) => _nextKeyId = value;

  /// Gets the current next key ID.
  int get nextKeyId => _nextKeyId;

  /// Generates a new identity key pair.
  ///
  /// Returns an [IdentityKeyPair] containing:
  /// - Ed25519 signing key pair
  /// - X25519 DH key pair
  Future<IdentityKeyPair> generateIdentityKeyPair() async {
    final signKeyPair = await _ed25519.generateKeyPair();
    final dhKeyPair = await _x25519.generateKeyPair();

    return IdentityKeyPair(
      signPublicKey: signKeyPair.publicKey,
      signPrivateKey: signKeyPair.privateKey,
      dhPublicKey: dhKeyPair.publicKey,
      dhPrivateKey: dhKeyPair.privateKey,
    );
  }

  /// Generates a new signed prekey.
  ///
  /// [identitySignPrivateKey] - Ed25519 private key for signing.
  ///
  /// Returns a [SignedPrekey] with the public key signed by the identity key.
  Future<SignedPrekey> generateSignedPrekey({
    required Uint8List identitySignPrivateKey,
  }) async {
    final keyPair = await _x25519.generateKeyPair();
    final keyId = _nextKeyId++;

    // Sign the public key with the identity signing key
    final signature = await _ed25519.sign(
      message: keyPair.publicKey,
      privateKey: identitySignPrivateKey,
    );

    return SignedPrekey(
      keyId: keyId,
      publicKey: keyPair.publicKey,
      privateKey: keyPair.privateKey,
      signature: signature,
      timestamp: DateTime.now(),
    );
  }

  /// Generates a batch of one-time prekeys.
  ///
  /// [count] - Number of one-time prekeys to generate.
  ///
  /// Returns a batch of [OneTimePrekey] objects ready for upload.
  Future<OneTimePrekeyBatch> generateOneTimePrekeys({
    int count = OneTimePrekeyBatch.recommendedPoolSize,
  }) async {
    final prekeys = <OneTimePrekey>[];

    for (var i = 0; i < count; i++) {
      final keyPair = await _x25519.generateKeyPair();
      final keyId = _nextKeyId++;

      prekeys.add(
        OneTimePrekey(
          keyId: keyId,
          publicKey: keyPair.publicKey,
          privateKey: keyPair.privateKey,
        ),
      );
    }

    return OneTimePrekeyBatch(prekeys: prekeys);
  }

  /// Generates a complete key bundle for a new user.
  ///
  /// This includes:
  /// - Identity key pair
  /// - Signed prekey
  /// - Initial batch of one-time prekeys
  ///
  /// Returns an [OwnKeyBundle] ready for storage and upload.
  Future<OwnKeyBundle> generateFullKeyBundle() async {
    final identity = await generateIdentityKeyPair();

    final signedPrekey = await generateSignedPrekey(
      identitySignPrivateKey: identity.signPrivateKey,
    );

    final oneTimePrekeyBatch = await generateOneTimePrekeys();

    final oneTimePrekeys = <int, OneTimePrekey>{};
    for (final pk in oneTimePrekeyBatch.prekeys) {
      oneTimePrekeys[pk.keyId] = pk;
    }

    return OwnKeyBundle(
      identity: identity,
      signedPrekey: signedPrekey,
      oneTimePrekeys: oneTimePrekeys,
    );
  }

  /// Generates a new ephemeral key pair for X3DH.
  ///
  /// Ephemeral keys are used once during initial key agreement.
  Future<X25519KeyPair> generateEphemeralKeyPair() async =>
      _x25519.generateKeyPair();

  /// Generates a new ratchet key pair for Double Ratchet.
  ///
  /// Ratchet keys are rotated with each message exchange.
  Future<X25519KeyPair> generateRatchetKeyPair() async =>
      _x25519.generateKeyPair();
}
