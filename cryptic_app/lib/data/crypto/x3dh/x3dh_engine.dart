// lib/data/crypto/x3dh/x3dh_engine.dart
//
// X3DH (Extended Triple Diffie-Hellman) Key Agreement Protocol
//
// Implements the sender (Alice) and receiver (Bob) sides of the X3DH protocol
// for establishing secure sessions with forward secrecy.
//

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/constants/crypto_constants.dart';
import '../../../core/errors/app_exceptions.dart';
import '../keys/key_bundle.dart';
import '../keys/keys.dart';
import '../primitives/chacha20_poly1305_service.dart';
import '../primitives/ed25519_service.dart';
import '../primitives/hkdf_service.dart';
import '../primitives/x25519_service.dart';

/// Result of X3DH sender initialization.
class X3dhSenderResult {
  /// Creates an X3DH sender result.
  const X3dhSenderResult({
    required this.messageBlob,
    required this.messageId,
    required this.sessionKey,
    required this.ephemeralKeyPair,
  });

  /// The encrypted message blob to send to the recipient.
  final X3dhMessageBlob messageBlob;

  /// Unique identifier for this message.
  final Uint8List messageId;

  /// The derived session key (32 bytes) for Double Ratchet initialization.
  final Uint8List sessionKey;

  /// The ephemeral keypair that becomes the initial Double Ratchet DH keypair.
  final X25519KeyPair ephemeralKeyPair;
}

/// Result of X3DH receiver decryption.
class X3dhReceiverResult {
  /// Creates an X3DH receiver result.
  const X3dhReceiverResult({
    required this.plaintext,
    required this.messageId,
    required this.sessionKey,
    required this.senderEphemeralPublic,
    required this.senderIdentityDhPublic,
  });

  /// The decrypted plaintext message.
  final Uint8List plaintext;

  /// The message ID from the sender.
  final Uint8List messageId;

  /// The derived session key (32 bytes) for Double Ratchet initialization.
  final Uint8List sessionKey;

  /// Sender's ephemeral public key (becomes their initial ratchet DH key).
  final Uint8List senderEphemeralPublic;

  /// Sender's identity DH public key.
  final Uint8List senderIdentityDhPublic;
}

/// X3DH encrypted message blob structure.
class X3dhMessageBlob {
  /// Creates an X3DH message blob.
  const X3dhMessageBlob({
    required this.metadata,
    required this.signature,
    required this.ciphertext,
    required this.nonce,
  });

  /// Message metadata (version, keys, IDs, timestamp).
  final X3dhMetadata metadata;

  /// Ed25519 signature over the metadata.
  final Uint8List signature;

  /// ChaCha20-Poly1305 encrypted message.
  final Uint8List ciphertext;

  /// Nonce used for encryption.
  final Uint8List nonce;

  /// Converts to a map for JSON serialization.
  Map<String, dynamic> toMap() {
    return {
      'metadata': metadata.toMap(),
      'signature': base64Encode(signature),
      'ciphertext': base64Encode(ciphertext),
      'nonce': base64Encode(nonce),
    };
  }

  /// Creates from a map (e.g., from JSON).
  factory X3dhMessageBlob.fromMap(Map<String, dynamic> map) {
    return X3dhMessageBlob(
      metadata: X3dhMetadata.fromMap(map['metadata'] as Map<String, dynamic>),
      signature: base64Decode(map['signature'] as String),
      ciphertext: base64Decode(map['ciphertext'] as String),
      nonce: base64Decode(map['nonce'] as String),
    );
  }
}

/// X3DH message metadata.
class X3dhMetadata {
  /// Creates X3DH metadata.
  const X3dhMetadata({
    required this.version,
    required this.type,
    required this.senderId,
    required this.senderIdentityDhPublic,
    required this.senderIdentitySignPublic,
    required this.recipientId,
    required this.ephemeralPublic,
    this.otpkId,
    required this.messageId,
    required this.timestamp,
  });

  /// Protocol version.
  final int version;

  /// Message type (e.g., "X3DH_INIT").
  final String type;

  /// Sender's key ID.
  final Uint8List senderId;

  /// Sender's identity DH public key.
  final Uint8List senderIdentityDhPublic;

  /// Sender's identity signing public key.
  final Uint8List senderIdentitySignPublic;

  /// Recipient's key ID.
  final Uint8List recipientId;

  /// Ephemeral public key for this message.
  final Uint8List ephemeralPublic;

  /// One-time prekey ID used (null if none available).
  final Uint8List? otpkId;

  /// Unique message identifier.
  final Uint8List messageId;

  /// Message timestamp (Unix seconds).
  final int timestamp;

  /// Converts to a map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'type': type,
      'sender_id': base64Encode(senderId),
      'sender_identity_dh_public': base64Encode(senderIdentityDhPublic),
      'sender_identity_sign_public': base64Encode(senderIdentitySignPublic),
      'recipient_id': base64Encode(recipientId),
      'ephemeral_public': base64Encode(ephemeralPublic),
      'otpk_id': otpkId != null ? base64Encode(otpkId!) : null,
      'message_id': base64Encode(messageId),
      'timestamp': timestamp,
    };
  }

  /// Serializes metadata to bytes for signing.
  Uint8List toBytes() {
    // Use JSON encoding for consistent cross-platform serialization
    final json = jsonEncode(toMap());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Creates from a map.
  factory X3dhMetadata.fromMap(Map<String, dynamic> map) {
    return X3dhMetadata(
      version: map['version'] as int,
      type: map['type'] as String,
      senderId: base64Decode(map['sender_id'] as String),
      senderIdentityDhPublic:
          base64Decode(map['sender_identity_dh_public'] as String),
      senderIdentitySignPublic:
          base64Decode(map['sender_identity_sign_public'] as String),
      recipientId: base64Decode(map['recipient_id'] as String),
      ephemeralPublic: base64Decode(map['ephemeral_public'] as String),
      otpkId: map['otpk_id'] != null
          ? base64Decode(map['otpk_id'] as String)
          : null,
      messageId: base64Decode(map['message_id'] as String),
      timestamp: map['timestamp'] as int,
    );
  }
}

/// X3DH Key Agreement Engine.
///
/// Implements the X3DH protocol for establishing secure end-to-end encrypted
/// sessions between two parties. X3DH provides:
///
/// - **Forward Secrecy**: Compromise of long-term keys doesn't compromise past messages
/// - **Cryptographic Deniability**: Messages can't be cryptographically proven to be from sender
/// - **Asynchronous**: Can establish session without recipient being online
///
/// The protocol performs 3 or 4 Diffie-Hellman exchanges:
/// - DH1: Sender Identity × Recipient Signed Prekey
/// - DH2: Sender Ephemeral × Recipient Identity
/// - DH3: Sender Ephemeral × Recipient Signed Prekey
/// - DH4: Sender Ephemeral × Recipient One-Time Prekey (optional)
class X3dhEngine {
  /// Creates an X3DH engine with the required crypto services.
  X3dhEngine({
    Ed25519Service? ed25519,
    X25519Service? x25519,
    HkdfService? hkdf,
    ChaCha20Poly1305Service? chacha,
  })  : _ed25519 = ed25519 ?? Ed25519Service(),
        _x25519 = x25519 ?? X25519Service(),
        _hkdf = hkdf ?? HkdfService(),
        _chacha = chacha ?? ChaCha20Poly1305Service();

  final Ed25519Service _ed25519;
  final X25519Service _x25519;
  final HkdfService _hkdf;
  final ChaCha20Poly1305Service _chacha;

  /// Sender initialization (Alice's perspective).
  ///
  /// Performs X3DH key agreement and encrypts the first message.
  ///
  /// [senderKeys] - Sender's identity and key material.
  /// [recipientBundle] - Recipient's public key bundle from server.
  /// [plaintext] - The message to encrypt.
  ///
  /// Returns the encrypted message blob, session key, and ephemeral keypair.
  Future<X3dhSenderResult> senderInit({
    required OwnKeyBundle senderKeys,
    required KeyBundle recipientBundle,
    required Uint8List plaintext,
  }) async {
    // 1. Verify recipient's signed prekey signature
    final isValid = await _ed25519.verify(
      message: recipientBundle.signedPrekey.publicKey,
      signature: recipientBundle.signedPrekey.signature,
      publicKey: recipientBundle.identitySignKey,
    );

    if (!isValid) {
      throw const CryptoException('Invalid signed prekey signature');
    }

    // 2. Generate ephemeral keypair for this session
    final ephemeralKeyPair = await _x25519.generateKeyPair();

    // 3. Perform DH exchanges
    // DH1: Sender Identity × Recipient Signed Prekey
    final dh1 = await _x25519.computeSharedSecret(
      privateKey: senderKeys.identity.dhPrivateKey,
      publicKey: recipientBundle.signedPrekey.publicKey,
    );

    // DH2: Sender Ephemeral × Recipient Identity DH
    final dh2 = await _x25519.computeSharedSecret(
      privateKey: ephemeralKeyPair.privateKey,
      publicKey: recipientBundle.identityDhKey,
    );

    // DH3: Sender Ephemeral × Recipient Signed Prekey
    final dh3 = await _x25519.computeSharedSecret(
      privateKey: ephemeralKeyPair.privateKey,
      publicKey: recipientBundle.signedPrekey.publicKey,
    );

    // DH4: Sender Ephemeral × Recipient One-Time Prekey (optional)
    Uint8List? dh4;
    Uint8List? otpkId;
    if (recipientBundle.hasOneTimePrekey) {
      dh4 = await _x25519.computeSharedSecret(
        privateKey: ephemeralKeyPair.privateKey,
        publicKey: recipientBundle.oneTimePrekey!.publicKey,
      );
      // Convert key ID to bytes
      otpkId = _intToBytes(recipientBundle.oneTimePrekey!.keyId);
    }

    // 4. Derive session key from combined DH outputs
    final dhOutputs = [dh1, dh2, dh3];
    if (dh4 != null) {
      dhOutputs.add(dh4);
    }

    final sessionKey = await _hkdf.deriveX3dhSecret(
      dhOutputs: dhOutputs,
      info: CryptoConstants.x3dhInfo,
    );

    // 5. Generate message ID
    final messageId = _chacha.generateNonce(); // 12 bytes for message ID
    // Extend to 16 bytes for consistency with Erlang
    final fullMessageId = Uint8List(16);
    fullMessageId.setRange(0, 12, messageId);
    fullMessageId.setRange(12, 16, _chacha.generateNonce().sublist(0, 4));

    // 6. Create metadata
    final metadata = X3dhMetadata(
      version: 1,
      type: 'X3DH_INIT',
      senderId: senderKeys.identity.signPublicKey.sublist(0, 8), // First 8 bytes as ID
      senderIdentityDhPublic: senderKeys.identity.dhPublicKey,
      senderIdentitySignPublic: senderKeys.identity.signPublicKey,
      recipientId: recipientBundle.identitySignKey.sublist(0, 8),
      ephemeralPublic: ephemeralKeyPair.publicKey,
      otpkId: otpkId,
      messageId: fullMessageId,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    // 7. Sign metadata
    final metadataBytes = metadata.toBytes();
    final signature = await _ed25519.sign(
      message: metadataBytes,
      privateKey: senderKeys.identity.signPrivateKey,
    );

    // 8. Encrypt plaintext with session key
    final encrypted = await _chacha.encrypt(
      plaintext: plaintext,
      key: sessionKey,
    );

    // 9. Build message blob (ciphertext includes tag appended)
    final messageBlob = X3dhMessageBlob(
      metadata: metadata,
      signature: signature,
      ciphertext: encrypted.ciphertextWithTag,
      nonce: encrypted.nonce,
    );

    return X3dhSenderResult(
      messageBlob: messageBlob,
      messageId: fullMessageId,
      sessionKey: sessionKey,
      ephemeralKeyPair: ephemeralKeyPair,
    );
  }

  /// Receiver decryption (Bob's perspective).
  ///
  /// Performs X3DH key derivation and decrypts the first message.
  ///
  /// [receiverKeys] - Receiver's identity and key material.
  /// [messageBlob] - The X3DH message blob from sender.
  /// [findOtpkPrivate] - Function to find OTPK private key by ID.
  ///
  /// Returns the decrypted message and session key.
  Future<X3dhReceiverResult> receiverDecrypt({
    required OwnKeyBundle receiverKeys,
    required X3dhMessageBlob messageBlob,
    Uint8List? Function(int keyId)? findOtpkPrivate,
  }) async {
    final metadata = messageBlob.metadata;

    // 1. Verify sender's signature over metadata
    final metadataBytes = metadata.toBytes();
    final isValid = await _ed25519.verify(
      message: metadataBytes,
      signature: messageBlob.signature,
      publicKey: metadata.senderIdentitySignPublic,
    );

    if (!isValid) {
      throw const CryptoException('Invalid message signature');
    }

    // 2. Perform DH exchanges (same as sender, from receiver's perspective)
    // DH1: Receiver Signed Prekey × Sender Identity DH
    final dh1 = await _x25519.computeSharedSecret(
      privateKey: receiverKeys.signedPrekey.privateKey,
      publicKey: metadata.senderIdentityDhPublic,
    );

    // DH2: Receiver Identity × Sender Ephemeral
    final dh2 = await _x25519.computeSharedSecret(
      privateKey: receiverKeys.identity.dhPrivateKey,
      publicKey: metadata.ephemeralPublic,
    );

    // DH3: Receiver Signed Prekey × Sender Ephemeral
    final dh3 = await _x25519.computeSharedSecret(
      privateKey: receiverKeys.signedPrekey.privateKey,
      publicKey: metadata.ephemeralPublic,
    );

    // DH4: Receiver One-Time Prekey × Sender Ephemeral (if used)
    Uint8List? dh4;
    if (metadata.otpkId != null) {
      final otpkKeyId = _bytesToInt(metadata.otpkId!);
      
      // Try findOtpkPrivate callback first
      Uint8List? otpkPrivate;
      if (findOtpkPrivate != null) {
        otpkPrivate = findOtpkPrivate(otpkKeyId);
      }
      
      // Fall back to receiver's key bundle
      otpkPrivate ??= receiverKeys.oneTimePrekeys[otpkKeyId]?.privateKey;

      if (otpkPrivate == null) {
        throw CryptoException('One-time prekey not found: $otpkKeyId');
      }

      dh4 = await _x25519.computeSharedSecret(
        privateKey: otpkPrivate,
        publicKey: metadata.ephemeralPublic,
      );
    }

    // 3. Derive session key from combined DH outputs
    final dhOutputs = [dh1, dh2, dh3];
    if (dh4 != null) {
      dhOutputs.add(dh4);
    }

    final sessionKey = await _hkdf.deriveX3dhSecret(
      dhOutputs: dhOutputs,
      info: CryptoConstants.x3dhInfo,
    );

    // 4. Decrypt message
    final plaintext = await _chacha.decrypt(
      ciphertext: messageBlob.ciphertext,
      key: sessionKey,
      nonce: messageBlob.nonce,
    );

    return X3dhReceiverResult(
      plaintext: plaintext,
      messageId: metadata.messageId,
      sessionKey: sessionKey,
      senderEphemeralPublic: metadata.ephemeralPublic,
      senderIdentityDhPublic: metadata.senderIdentityDhPublic,
    );
  }

  /// Converts an integer to 8 bytes (big-endian).
  Uint8List _intToBytes(int value) {
    final bytes = Uint8List(8);
    for (var i = 7; i >= 0; i--) {
      bytes[i] = value & 0xff;
      value >>= 8;
    }
    return bytes;
  }

  /// Converts 8 bytes (big-endian) to an integer.
  int _bytesToInt(Uint8List bytes) {
    var value = 0;
    for (var i = 0; i < bytes.length && i < 8; i++) {
      value = (value << 8) | bytes[i];
    }
    return value;
  }
}
