# Flutter Mobile App Architecture for Cryptic

This document outlines the architecture for a Flutter mobile application that
implements the Cryptic end-to-end encrypted messaging protocol.

## Implementation Status (April 2026)

**✅ M8 Mobile Enrollment Complete** - End-to-end: QR enrollment → mTLS → encrypted chat

| Component | Status | Notes |
|-----------|--------|-------|
| X3DH Key Agreement | ✅ Complete | Interoperates with Erlang server |
| Double Ratchet | ✅ Complete | Blake2b KDF matching libsodium |
| WebSocket Client | ✅ Complete | mTLS with client certificates |
| Protocol Messages | ✅ Complete | JSON encoding/decoding, Erlang char-list tolerance |
| Key Storage | ✅ Complete | flutter_secure_storage (iOS Keychain) |
| Session Management | ✅ Complete | Persistent ratchet sessions |
| Chat UI | ✅ Complete | Send/receive messages |
| Users List | ✅ Complete | Online users from server |
| Connection Status | ✅ Complete | Real-time status updates |
| Message History | 🔄 Partial | In-memory only (SQLCipher DB pending) |
| Mobile Enrollment | ✅ Complete | QR scan → ECDSA P-256 CSR (Ed25519-signed) → mTLS cert |
| Certificate Storage | ✅ Complete | Cert/key in iOS Keychain via flutter_secure_storage |
| Settings Screen | 🔄 Planned | Basic structure only |
| Certificate Renewal | 📋 Planned | No renewal flow yet |
| Notifications | 📋 Planned | Not yet implemented |

## Overview

The Flutter app is a faithful port of the Erlang client architecture,
maintaining the same cryptographic protocols (X3DH, Double Ratchet) and
WebSocket communication while adapting to Flutter's reactive UI patterns.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                         UI Layer (Flutter)                      │
│  - ChatScreen, UsersScreen, LoginScreen                         │
│  - State Management (Riverpod providers)                        │
└─────────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────────┐
│                      Business Logic Layer                       │
│  - CrypticEngine (orchestrates crypto + network)                │
│  - MessageProcessor (encrypt/decrypt messages)                  │
│  - SessionManager (manage per-peer ratchet sessions)            │
└─────────────────────────────────────────────────────────────────┘
                              ↕
┌────────────────────────────┬────────────────────────────────────┐
│     Crypto Layer           │        Network Layer               │
│  - X3DH Protocol           │  - WebSocket Client (mTLS)         │
│  - Double Ratchet          │  - Protocol Codec (JSON)           │
│  - Key Management          │  - Client/Server Messages          │
└────────────────────────────┴────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────────┐
│                       Storage Layer                             │
│  - Certificate Storage (mTLS certs via flutter_secure_storage)  │
│  - Secure Key Storage (identity keys, prekeys, sessions)        │
│  - Session Repository (persisted ratchet state)                 │
│  - Encrypted Preferences (app settings)                         │
│  - Message Database (sqflite_sqlcipher) - pending               │
└─────────────────────────────────────────────────────────────────┘
```

## Project Structure (Actual Implementation)

```
lib/
├── main.dart                              // App entry point with Riverpod
│
├── core/
│   ├── config/
│   │   └── app_config.dart               // AppConfig enum (dev/staging/prod)
│   ├── constants/
│   │   └── crypto_constants.dart         // Crypto params (key sizes, HKDF info)
│   ├── errors/
│   │   └── app_exceptions.dart           // CrypticException hierarchy
│   ├── theme/
│   │   ├── app_colors.dart               // Color palette
│   │   ├── app_text_styles.dart          // Typography
│   │   ├── app_theme.dart                // Light/dark ThemeData (Material 3)
│   │   └── theme.dart                    // Barrel export
│   └── utils/
│       └── logger.dart                   // AppLogger with redaction
│
├── domain/
│   ├── models/
│   │   ├── contact.dart                  // Contact + ContactStatus
│   │   ├── conversation.dart             // Conversation model
│   │   ├── message.dart                  // ChatMessage + MessageStatus/Direction
│   │   └── models.dart                   // Barrel export
│   ├── usecases/
│   │   ├── use_case.dart                 // UseCase/NoInputUseCase base + Result
│   │   ├── connect.dart                  // ConnectUseCase / DisconnectUseCase
│   │   ├── get_users.dart                // GetUsersUseCase
│   │   ├── initialize_session.dart       // InitializeSessionUseCase
│   │   ├── send_message.dart             // SendMessageUseCase
│   │   ├── upload_keys.dart              // UploadKeysUseCase (stub)
│   │   └── usecases.dart                 // Barrel export
│   └── services/
│       └── crypto/
│           └── crypto_services.dart      // Pointer to data/crypto
│
├── data/
│   ├── crypto/
│   │   ├── keys/
│   │   │   ├── identity_key_pair.dart    // IdentityKeyPair
│   │   │   ├── key_bundle.dart           // KeyBundle (X3DH)
│   │   │   ├── key_generator.dart        // KeyGenerator (Ed25519+X25519)
│   │   │   ├── one_time_prekey.dart      // OneTimePrekey
│   │   │   ├── signed_prekey.dart        // SignedPrekey
│   │   │   └── keys.dart                 // Barrel export
│   │   ├── primitives/
│   │   │   ├── chacha20_poly1305_service.dart  // AEAD encryption
│   │   │   ├── ed25519_service.dart            // Ed25519 signing
│   │   │   ├── hkdf_service.dart               // HMAC-based KDF (for X3DH)
│   │   │   ├── kdf_service.dart                // Blake2b KDF (Double Ratchet)
│   │   │   └── x25519_service.dart             // X25519 key exchange
│   │   ├── ratchet/
│   │   │   ├── double_ratchet.dart       // DoubleRatchet (encrypt/decrypt)
│   │   │   ├── ratchet_message.dart      // RatchetMessage format
│   │   │   ├── ratchet_state.dart        // RatchetState (per-peer)
│   │   │   └── ratchet.dart              // Barrel export
│   │   └── x3dh/
│   │       └── x3dh_engine.dart          // X3dhEngine (sender/receiver)
│   │
│   ├── engine/
│   │   ├── cryptic_engine.dart           // CrypticEngine - main orchestrator
│   │   ├── engine_state.dart             // EngineState, EngineEvent, enums
│   │   ├── message_processor.dart        // MessageProcessor (decode+decrypt)
│   │   ├── session_manager.dart          // SessionManager (per-peer ratchets)
│   │   └── engine.dart                   // Barrel export
│   │
│   ├── enrollment/
│   │   ├── enrollment_payload.dart       // EnrollmentEnvelope + Payload (QR v1/v2)
│   │   ├── enrollment_crypto.dart        // Argon2id, HMAC, AES-CBC, Ed25519 sign
│   │   ├── csr_generator.dart            // ECDSA P-256 keypair + PKCS#10 CSR
│   │   └── enrollment_service.dart       // Full enrollment orchestrator
│   │
│   ├── network/
│   │   ├── protocol/
│   │   │   ├── protocol_message.dart     // ProtocolMessage base, type enums
│   │   │   ├── client_messages.dart      // Outgoing message types (toJson)
│   │   │   ├── server_messages.dart      // Incoming message types (fromJson)
│   │   │   └── protocol_codec.dart       // ProtocolCodec + extensions
│   │   └── websocket/
│   │       ├── websocket_client.dart     // WebSocketClient (mTLS)
│   │       ├── mtls_config.dart          // MtlsConfig (PEM → SecurityContext)
│   │       ├── connection_manager.dart   // ConnectionManager (reconnect, heartbeat)
│   │       └── message_queue.dart        // MessageQueue (offline outbound)
│   │
│   ├── services/
│   │   └── authentication_service.dart   // AuthenticationService (cert → engine)
│   │
│   └── storage/
│       ├── storage.dart                  // Barrel export
│       ├── secure_storage/
│       │   ├── secure_storage_service.dart    // flutter_secure_storage wrapper
│       │   ├── certificate_storage_service.dart // mTLS cert/key/CA storage
│       │   ├── key_storage_service.dart       // Identity keys + session state
│       │   └── secure_storage.dart            // Barrel export
│       ├── repositories/
│       │   ├── key_repository.dart            // KeyRepository facade
│       │   ├── session_repository.dart        // SessionRepository facade
│       │   └── repositories.dart              // Barrel export
│       └── preferences/
│           ├── encrypted_preferences.dart     // EncryptedPreferences (settings)
│           └── preferences.dart               // Barrel export
│
├── presentation/
│   ├── app.dart                          // CrypticApp root (screen routing)
│   ├── providers/
│   │   ├── auth_provider.dart            // AuthNotifier + AuthStatus
│   │   ├── engine_provider.dart          // Engine Riverpod providers
│   │   ├── enrollment_provider.dart      // EnrollmentNotifier + status
│   │   ├── messages_provider.dart        // ConversationsNotifier
│   │   └── providers.dart                // Barrel export
│   ├── screens/
│   │   ├── splash_screen.dart            // Startup + auth check
│   │   ├── login_screen.dart             // Username/passphrase entry
│   │   ├── users_screen.dart             // Online users list (home screen)
│   │   ├── chat_screen.dart              // Chat conversation
│   │   ├── conversations_screen.dart     // Conversation list (alternate)
│   │   ├── screens.dart                  // Barrel export
│   │   └── enrollment/
│   │       ├── enrollment_flow_screen.dart     // Flow orchestrator
│   │       ├── qr_scanner_screen.dart          // QR code scanning
│   │       ├── passphrase_screen.dart          // Passphrase entry
│   │       └── enrollment_progress_screen.dart // Progress display
│   └── widgets/
│       ├── connection_status_banner.dart  // Connection state indicator
│       ├── conversation_tile.dart        // Conversation list item
│       ├── empty_state.dart              // Empty state placeholder
│       ├── loading_overlay.dart          // Loading overlay
│       ├── message_bubble.dart           // Chat message bubble
│       ├── message_input.dart            // Text input + send button
│       ├── user_avatar.dart              // Avatar with initials
│       └── widgets.dart                  // Barrel export
│
└── assets/
    └── certificates/                     // Bundled fallback certs (dev only)
        ├── ca.crt
        ├── client.crt
        └── client.key
```
## Core Components

> **Note**: The code samples below are illustrative pseudocode showing the
> conceptual design. For the actual implementation, see the source files in
> `lib/data/`. Key differences from the pseudocode and typical Signal implementations:
> - `CrypticEngine` takes concrete dependencies (`KeyRepository`, `SessionRepository`,
>   `WebSocketClient`) rather than abstract repository interfaces
> - Uses Blake2b KDF (matching libsodium) instead of HKDF for ratchet chain keys
> - Uses XOR mixing for root key updates instead of HKDF
> - `AuthenticationService` (not shown below) bridges certificate loading and engine setup
> - See [Critical Implementation Details](#critical-implementation-details) for specifics.

### 1. CrypticEngine (Port of `cryptic_engine.erl`)

The central orchestrator for all cryptographic operations and message handling.

```dart
class CrypticEngine {
  final String username;
  final CryptoRepository _crypto;
  final NetworkRepository _network;
  final StorageRepository _storage;
  
  IdentityKeys? _identityKeys;
  final Map<String, SessionState> _sessions = {};
  final Map<String, PrekeyBundle> _peerKeyBundles = {};
  
  StreamController<Message> _messageStream = StreamController.broadcast();
  StreamController<String> _systemMessageStream = StreamController.broadcast();
  
  // Initialize engine (load keys, connect to server)
  Future<void> initialize(String passphrase) async {
    // Load identity keys from secure storage
    _identityKeys = await _storage.loadIdentityKeys(username, passphrase);
    
    if (_identityKeys == null) {
      // First time: generate keys
      _identityKeys = await _crypto.generateIdentityKeys();
      await _storage.saveIdentityKeys(username, _identityKeys!, passphrase);
    }
    
    // Connect to WebSocket server
    await _network.connect(username);
    
    // Upload identity keys and prekey bundles to server
    await uploadKeys();
    
    // Listen for incoming messages
    _network.messageStream.listen(_handleServerMessage);
  }
  
  // Send encrypted message to peer
  Future<void> sendMessage(String toUser, String plaintext) async {
    // Get or create session with peer
    SessionState? session = _sessions[toUser];
    
    if (session == null) {
      // No session exists: perform X3DH
      await _initiateX3DHSession(toUser, plaintext);
    } else {
      // Session exists: use Double Ratchet
      await _sendRatchetMessage(toUser, plaintext, session);
    }
  }
  
  // Initialize X3DH session with peer
  Future<void> _initiateX3DHSession(String toUser, String plaintext) async {
    // Request peer's prekey bundle from server
    final bundle = await _network.requestKeyBundle(toUser);
    _peerKeyBundles[toUser] = bundle;
    
    // Perform X3DH key agreement
    final x3dhResult = await _crypto.performX3DH(
      identityKeys: _identityKeys!,
      peerBundle: bundle,
    );
    
    // Initialize Double Ratchet with shared secret
    final session = await _crypto.initializeRatchet(
      sharedSecret: x3dhResult.sharedKey,
      peerDHPublicKey: bundle.signedPrekeyPublic,
    );
    
    _sessions[toUser] = session;
    await _storage.saveSession(username, toUser, session);
    
    // Encrypt first message
    final encrypted = await _crypto.ratchetEncrypt(session, plaintext);
    
    // Send X3DH initial message
    await _network.sendX3DHMessage(
      toUser: toUser,
      identityKey: x3dhResult.ephemeralPublic,
      ephemeralKey: x3dhResult.ephemeralPublic,
      usedOTPKId: bundle.oneTimePrekey?.keyId,
      ciphertext: encrypted.ciphertext,
    );
  }
  
  // Send message using existing ratchet session
  Future<void> _sendRatchetMessage(
    String toUser,
    String plaintext,
    SessionState session,
  ) async {
    // Encrypt with Double Ratchet
    final encrypted = await _crypto.ratchetEncrypt(session, plaintext);
    
    // Update session state
    _sessions[toUser] = encrypted.newSession;
    await _storage.saveSession(username, toUser, encrypted.newSession);
    
    // Send ratchet message
    await _network.sendRatchetMessage(
      toUser: toUser,
      dhPublic: encrypted.dhPublic,
      previousChainLength: encrypted.previousChainLength,
      messageNumber: encrypted.messageNumber,
      ciphertext: encrypted.ciphertext,
    );
  }
  
  // Handle incoming message from server
  Future<void> _handleServerMessage(ServerMessage msg) async {
    switch (msg.type) {
      case MessageType.x3dh:
        await _handleX3DHMessage(msg as X3DHMessage);
        break;
      case MessageType.ratchet:
        await _handleRatchetMessage(msg as RatchetMessage);
        break;
      case MessageType.keyBundle:
        await _handleKeyBundle(msg as KeyBundleMessage);
        break;
      case MessageType.userStatus:
        _systemMessageStream.add('User ${msg.username} is ${msg.status}');
        break;
      default:
        _systemMessageStream.add('Unknown message type: ${msg.type}');
    }
  }
  
  // Handle incoming X3DH message
  Future<void> _handleX3DHMessage(X3DHMessage msg) async {
    // Perform X3DH as responder
    final x3dhResult = await _crypto.receiveX3DH(
      identityKeys: _identityKeys!,
      peerIdentityKey: msg.identityKey,
      peerEphemeralKey: msg.ephemeralKey,
      usedOTPKId: msg.usedOTPKId,
    );
    
    // Initialize Double Ratchet
    final session = await _crypto.initializeRatchetAsResponder(
      sharedSecret: x3dhResult.sharedKey,
      peerDHPublicKey: msg.identityKey,
    );
    
    _sessions[msg.fromUser] = session;
    await _storage.saveSession(username, msg.fromUser, session);
    
    // Decrypt message
    final decrypted = await _crypto.ratchetDecrypt(
      session,
      msg.ciphertext,
      dhPublic: msg.ephemeralKey,
      previousChainLength: 0,
      messageNumber: 0,
    );
    
    _sessions[msg.fromUser] = decrypted.newSession;
    await _storage.saveSession(username, msg.fromUser, decrypted.newSession);
    
    // Deliver to UI
    _messageStream.add(Message(
      from: msg.fromUser,
      text: decrypted.plaintext,
      timestamp: DateTime.now(),
    ));
    
    // Save to database
    await _storage.saveMessage(username, msg.fromUser, decrypted.plaintext);
  }
  
  // Handle incoming ratchet message
  Future<void> _handleRatchetMessage(RatchetMessage msg) async {
    final session = _sessions[msg.fromUser];
    if (session == null) {
      _systemMessageStream.add('No session for ${msg.fromUser}');
      return;
    }
    
    // Decrypt with Double Ratchet
    final decrypted = await _crypto.ratchetDecrypt(
      session,
      msg.ciphertext,
      dhPublic: msg.dhPublic,
      previousChainLength: msg.previousChainLength,
      messageNumber: msg.messageNumber,
    );
    
    _sessions[msg.fromUser] = decrypted.newSession;
    await _storage.saveSession(username, msg.fromUser, decrypted.newSession);
    
    // Deliver to UI
    _messageStream.add(Message(
      from: msg.fromUser,
      text: decrypted.plaintext,
      timestamp: DateTime.now(),
    ));
    
    // Save to database
    await _storage.saveMessage(username, msg.fromUser, decrypted.plaintext);
  }
  
  // Upload identity keys and prekeys to server
  Future<void> uploadKeys() async {
    // Generate one-time prekeys
    final oneTimePrekeys = await _crypto.generateOneTimePrekeys(count: 100);
    
    // Upload to server
    await _network.uploadIdentityKeys(_identityKeys!);
    await _network.uploadPrekeyBundle(oneTimePrekeys);
    
    _systemMessageStream.add('Keys uploaded successfully');
  }
  
  // Streams for UI
  Stream<Message> get messageStream => _messageStream.stream;
  Stream<String> get systemMessageStream => _systemMessageStream.stream;
}
```

### 2. WebSocket Client (Port of `cryptic_ws_client.erl`)

Handles mTLS WebSocket connection to server.

```dart
class WebSocketClient implements NetworkRepository {
  final String serverHost;
  final int serverPort;
  final String username;
  
  WebSocketChannel? _channel;
  final StreamController<ServerMessage> _messageController = 
      StreamController.broadcast();
  
  @override
  Stream<ServerMessage> get messageStream => _messageController.stream;
  
  @override
  Future<void> connect(String username) async {
    // Load mTLS certificates
    final cert = await _loadCertificate(username);
    final key = await _loadPrivateKey(username);
    final ca = await _loadCACertificate();
    
    // Create mTLS context
    final securityContext = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key)
      ..setTrustedCertificates(ca);
    
    // Connect WebSocket with mTLS
    final uri = Uri.parse('wss://$serverHost:$serverPort');
    final socket = await SecureSocket.connect(
      serverHost,
      serverPort,
      context: securityContext,
    );
    
    _channel = IOWebSocketChannel(WebSocket.fromUpgradedSocket(
      socket,
      serverSide: false,
    ));
    
    // Listen for messages
    _channel!.stream.listen(
      (data) => _handleMessage(data),
      onError: (error) => _handleError(error),
      onDone: () => _handleDisconnect(),
    );
  }
  
  void _handleMessage(dynamic data) {
    final json = jsonDecode(data as String);
    final message = ServerMessage.fromJson(json);
    _messageController.add(message);
  }
  
  @override
  Future<void> sendX3DHMessage({
    required String toUser,
    required Uint8List identityKey,
    required Uint8List ephemeralKey,
    int? usedOTPKId,
    required Uint8List ciphertext,
  }) async {
    final message = {
      'type': 'x3dh',
      'message_id': Uuid().v4(),
      'from_user': username,
      'to_user': toUser,
      'identity_key': base64Encode(identityKey),
      'ephemeral_key': base64Encode(ephemeralKey),
      'used_one_time_prekey_id': usedOTPKId,
      'ciphertext': base64Encode(ciphertext),
    };
    
    _channel!.sink.add(jsonEncode(message));
  }
  
  @override
  Future<void> sendRatchetMessage({
    required String toUser,
    required Uint8List dhPublic,
    required int previousChainLength,
    required int messageNumber,
    required Uint8List ciphertext,
  }) async {
    final message = {
      'type': 'ratchet',
      'message_id': Uuid().v4(),
      'from_user': username,
      'to_user': toUser,
      'dh_public': base64Encode(dhPublic),
      'previous_chain_length': previousChainLength,
      'message_number': messageNumber,
      'ciphertext': base64Encode(ciphertext),
    };
    
    _channel!.sink.add(jsonEncode(message));
  }
  
  @override
  Future<PrekeyBundle> requestKeyBundle(String username) async {
    final message = {
      'type': 'get_key_bundle',
      'username': username,
    };
    
    _channel!.sink.add(jsonEncode(message));
    
    // Wait for key_bundle response
    final response = await messageStream
        .firstWhere((msg) => msg.type == MessageType.keyBundle);
    
    return (response as KeyBundleMessage).bundle;
  }
}
```

### 3. X3DH Implementation (Port of `cryptic_lib.erl`)

```dart
class X3DHEngine {
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();
  final HKDF _hkdf = HKDF();
  
  // Generate identity key pairs
  Future<IdentityKeys> generateIdentityKeys() async {
    // Signing key pair (Ed25519)
    final signKeyPair = _ed25519.generateKeyPair();
    
    // DH key pair (X25519)
    final dhKeyPair = _x25519.generateKeyPair();
    
    // Signed prekey
    final signedPrekeyPair = _x25519.generateKeyPair();
    final signedPrekeySignature = _ed25519.sign(
      signKeyPair.privateKey,
      signedPrekeyPair.publicKey,
    );
    
    return IdentityKeys(
      identitySignPublic: signKeyPair.publicKey,
      identitySignPrivate: signKeyPair.privateKey,
      identityDHPublic: dhKeyPair.publicKey,
      identityDHPrivate: dhKeyPair.privateKey,
      signedPrekeyPublic: signedPrekeyPair.publicKey,
      signedPrekeyPrivate: signedPrekeyPair.privateKey,
      signedPrekeySignature: signedPrekeySignature,
      signedPrekeyId: 1,
    );
  }
  
  // Perform X3DH as initiator
  Future<X3DHResult> performX3DH({
    required IdentityKeys identityKeys,
    required PrekeyBundle peerBundle,
  }) async {
    // Verify signed prekey signature
    final isValid = _ed25519.verify(
      peerBundle.identitySignKey,
      peerBundle.signedPrekeyPublic,
      peerBundle.signedPrekeySignature,
    );
    
    if (!isValid) {
      throw Exception('Invalid signed prekey signature');
    }
    
    // Generate ephemeral key pair
    final ephemeralKeyPair = _x25519.generateKeyPair();
    
    // Perform 4 DH operations
    final dh1 = _x25519.computeSharedSecret(
      identityKeys.identityDHPrivate,
      peerBundle.signedPrekeyPublic,
    );
    
    final dh2 = _x25519.computeSharedSecret(
      ephemeralKeyPair.privateKey,
      peerBundle.identityDHKey,
    );
    
    final dh3 = _x25519.computeSharedSecret(
      ephemeralKeyPair.privateKey,
      peerBundle.signedPrekeyPublic,
    );
    
    final dh4 = peerBundle.oneTimePrekey != null
        ? _x25519.computeSharedSecret(
            ephemeralKeyPair.privateKey,
            peerBundle.oneTimePrekey!.publicKey,
          )
        : Uint8List(32); // Zero bytes if no OPK
    
    // Concatenate DH outputs
    final dhOutput = Uint8List.fromList([
      ...dh1,
      ...dh2,
      ...dh3,
      ...dh4,
    ]);
    
    // Derive shared secret with HKDF
    final sharedKey = _hkdf.deriveKey(
      dhOutput,
      salt: Uint8List(32),
      info: utf8.encode('Cryptic X3DH'),
      length: 32,
    );
    
    return X3DHResult(
      sharedKey: sharedKey,
      ephemeralPublic: ephemeralKeyPair.publicKey,
    );
  }
  
  // Receive X3DH as responder
  Future<X3DHResult> receiveX3DH({
    required IdentityKeys identityKeys,
    required Uint8List peerIdentityKey,
    required Uint8List peerEphemeralKey,
    int? usedOTPKId,
  }) async {
    // Perform 4 DH operations (in reverse)
    final dh1 = _x25519.computeSharedSecret(
      identityKeys.signedPrekeyPrivate,
      peerIdentityKey,
    );
    
    final dh2 = _x25519.computeSharedSecret(
      identityKeys.identityDHPrivate,
      peerEphemeralKey,
    );
    
    final dh3 = _x25519.computeSharedSecret(
      identityKeys.signedPrekeyPrivate,
      peerEphemeralKey,
    );
    
    // Get one-time prekey if used
    Uint8List? dh4;
    if (usedOTPKId != null) {
      final otpk = await _getOneTimePrekey(usedOTPKId);
      if (otpk != null) {
        dh4 = _x25519.computeSharedSecret(otpk, peerEphemeralKey);
      }
    }
    dh4 ??= Uint8List(32);
    
    // Concatenate DH outputs
    final dhOutput = Uint8List.fromList([
      ...dh1,
      ...dh2,
      ...dh3,
      ...dh4,
    ]);
    
    // Derive shared secret with HKDF
    final sharedKey = _hkdf.deriveKey(
      dhOutput,
      salt: Uint8List(32),
      info: utf8.encode('Cryptic X3DH'),
      length: 32,
    );
    
    return X3DHResult(
      sharedKey: sharedKey,
      ephemeralPublic: Uint8List(0), // Not used by responder
    );
  }
}
```

### 4. Double Ratchet Implementation (Port of `cryptic_double_ratchet.erl`)

```dart
class DoubleRatchet {
  final X25519 _x25519 = X25519();
  final HKDF _hkdf = HKDF();
  final ChaCha20Poly1305 _aead = ChaCha20Poly1305();
  
  // Initialize ratchet as initiator
  Future<SessionState> initialize({
    required Uint8List sharedSecret,
    required Uint8List peerDHPublicKey,
  }) async {
    // Derive root key and chain key from shared secret
    final rootKey = _hkdf.deriveKey(
      sharedSecret,
      salt: Uint8List(32),
      info: utf8.encode('Cryptic Root Key'),
      length: 32,
    );
    
    // Generate initial DH key pair
    final dhKeyPair = _x25519.generateKeyPair();
    
    // Perform DH ratchet step
    final dhOutput = _x25519.computeSharedSecret(
      dhKeyPair.privateKey,
      peerDHPublicKey,
    );
    
    // Derive new root key and sending chain key
    final kdfOutput = _hkdf.deriveKey(
      Uint8List.fromList([...rootKey, ...dhOutput]),
      salt: Uint8List(32),
      info: utf8.encode('Cryptic Chain Key'),
      length: 64,
    );
    
    final newRootKey = kdfOutput.sublist(0, 32);
    final sendingChainKey = kdfOutput.sublist(32, 64);
    
    return SessionState(
      rootKey: newRootKey,
      sendingChainKey: sendingChainKey,
      receivingChainKey: null,
      dhKeyPair: dhKeyPair,
      peerDHPublic: peerDHPublicKey,
      sendingChainLength: 0,
      receivingChainLength: 0,
      previousSendingChainLength: 0,
      skippedMessageKeys: {},
    );
  }
  
  // Encrypt message
  Future<EncryptedMessage> encrypt(
    SessionState session,
    String plaintext,
  ) async {
    // Derive message key from chain key
    final messageKey = _hkdf.deriveKey(
      session.sendingChainKey!,
      salt: Uint8List(32),
      info: utf8.encode('Cryptic Message Key'),
      length: 32,
    );
    
    // Advance chain key
    final newChainKey = _hkdf.deriveKey(
      session.sendingChainKey!,
      salt: Uint8List(32),
      info: utf8.encode('Cryptic Chain Step'),
      length: 32,
    );
    
    // Encrypt plaintext
    final nonce = _generateNonce();
    final ciphertext = _aead.encrypt(
      key: messageKey,
      nonce: nonce,
      plaintext: utf8.encode(plaintext),
      additionalData: Uint8List(0),
    );
    
    final newSession = session.copyWith(
      sendingChainKey: newChainKey,
      sendingChainLength: session.sendingChainLength + 1,
    );
    
    return EncryptedMessage(
      ciphertext: Uint8List.fromList([...nonce, ...ciphertext]),
      dhPublic: session.dhKeyPair.publicKey,
      previousChainLength: session.previousSendingChainLength,
      messageNumber: session.sendingChainLength,
      newSession: newSession,
    );
  }
  
  // Decrypt message
  Future<DecryptedMessage> decrypt(
    SessionState session,
    Uint8List ciphertext, {
    required Uint8List dhPublic,
    required int previousChainLength,
    required int messageNumber,
  }) async {
    // Check if we need to perform DH ratchet
    SessionState workingSession = session;
    if (!_bytesEqual(dhPublic, session.peerDHPublic!)) {
      workingSession = await _performDHRatchet(session, dhPublic);
    }
    
    // Check for skipped messages
    final skippedKey = '${base64Encode(dhPublic)}:$messageNumber';
    if (workingSession.skippedMessageKeys.containsKey(skippedKey)) {
      final messageKey = workingSession.skippedMessageKeys[skippedKey]!;
      return await _decryptWithKey(ciphertext, messageKey, workingSession);
    }
    
    // Skip messages if needed
    while (workingSession.receivingChainLength < messageNumber) {
      final skippedMessageKey = _deriveMessageKey(
        workingSession.receivingChainKey!,
      );
      
      final key = '${base64Encode(dhPublic)}:${workingSession.receivingChainLength}';
      workingSession = workingSession.copyWith(
        skippedMessageKeys: {
          ...workingSession.skippedMessageKeys,
          key: skippedMessageKey,
        },
      );
      
      workingSession = _advanceChainKey(workingSession, isReceiving: true);
    }
    
    // Derive message key
    final messageKey = _deriveMessageKey(workingSession.receivingChainKey!);
    
    // Advance chain key
    final newSession = _advanceChainKey(workingSession, isReceiving: true);
    
    return await _decryptWithKey(ciphertext, messageKey, newSession);
  }
  
  Future<SessionState> _performDHRatchet(
    SessionState session,
    Uint8List peerDHPublic,
  ) async {
    // Generate new DH key pair
    final newDHKeyPair = _x25519.generateKeyPair();
    
    // Perform DH
    final dhOutput = _x25519.computeSharedSecret(
      newDHKeyPair.privateKey,
      peerDHPublic,
    );
    
    // Derive new root key and receiving chain key
    final kdfOutput = _hkdf.deriveKey(
      Uint8List.fromList([...session.rootKey, ...dhOutput]),
      salt: Uint8List(32),
      info: utf8.encode('Cryptic Chain Key'),
      length: 64,
    );
    
    final newRootKey = kdfOutput.sublist(0, 32);
    final receivingChainKey = kdfOutput.sublist(32, 64);
    
    // Perform sending DH ratchet
    final sendingDHOutput = _x25519.computeSharedSecret(
      newDHKeyPair.privateKey,
      peerDHPublic,
    );
    
    final sendingKdfOutput = _hkdf.deriveKey(
      Uint8List.fromList([...newRootKey, ...sendingDHOutput]),
      salt: Uint8List(32),
      info: utf8.encode('Cryptic Chain Key'),
      length: 64,
    );
    
    final finalRootKey = sendingKdfOutput.sublist(0, 32);
    final sendingChainKey = sendingKdfOutput.sublist(32, 64);
    
    return session.copyWith(
      rootKey: finalRootKey,
      sendingChainKey: sendingChainKey,
      receivingChainKey: receivingChainKey,
      dhKeyPair: newDHKeyPair,
      peerDHPublic: peerDHPublic,
      previousSendingChainLength: session.sendingChainLength,
      sendingChainLength: 0,
      receivingChainLength: 0,
    );
  }
  
  Uint8List _deriveMessageKey(Uint8List chainKey) {
    return _hkdf.deriveKey(
      chainKey,
      salt: Uint8List(32),
      info: utf8.encode('Cryptic Message Key'),
      length: 32,
    );
  }
  
  SessionState _advanceChainKey(SessionState session, {required bool isReceiving}) {
    final chainKey = isReceiving 
        ? session.receivingChainKey! 
        : session.sendingChainKey!;
    
    final newChainKey = _hkdf.deriveKey(
      chainKey,
      salt: Uint8List(32),
      info: utf8.encode('Cryptic Chain Step'),
      length: 32,
    );
    
    if (isReceiving) {
      return session.copyWith(
        receivingChainKey: newChainKey,
        receivingChainLength: session.receivingChainLength + 1,
      );
    } else {
      return session.copyWith(
        sendingChainKey: newChainKey,
        sendingChainLength: session.sendingChainLength + 1,
      );
    }
  }
  
  Future<DecryptedMessage> _decryptWithKey(
    Uint8List ciphertext,
    Uint8List messageKey,
    SessionState session,
  ) async {
    // Extract nonce (first 12 bytes)
    final nonce = ciphertext.sublist(0, 12);
    final encrypted = ciphertext.sublist(12);
    
    // Decrypt
    final plaintext = _aead.decrypt(
      key: messageKey,
      nonce: nonce,
      ciphertext: encrypted,
      additionalData: Uint8List(0),
    );
    
    return DecryptedMessage(
      plaintext: utf8.decode(plaintext),
      newSession: session,
    );
  }
  
  Uint8List _generateNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(12, (_) => random.nextInt(256)),
    );
  }
  
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
```

## UI Layer with Riverpod

### State Management

The app uses Riverpod providers organized across four provider files:

```dart
// auth_provider.dart — Owns the CrypticEngine lifecycle
final authProvider = StateNotifierProvider<AuthNotifier, AuthStatus>(...);
// AuthNotifier holds CrypticEngine?, exposes authenticate/setup/logout/checkAuthState
// AuthStatus: { isAuthenticated, needsSetup, error }

// Derived provider so other providers can access the engine
final authenticatedEngineProvider = Provider<CrypticEngine?>((ref) {
  final auth = ref.watch(authProvider);
  return auth.isAuthenticated ? ref.read(authProvider.notifier).engine : null;
});

// engine_provider.dart — Derived providers from engine state
final engineProvider = Provider<CrypticEngine?>((ref) =>
    ref.watch(authenticatedEngineProvider));

final engineStateProvider = StreamProvider<EngineState>((ref) {
  final engine = ref.watch(engineProvider);
  return engine?.stateChanges ?? Stream.value(EngineState.initial);
});

final engineEventsProvider = StreamProvider<EngineEvent>((ref) {
  final engine = ref.watch(engineProvider);
  return engine?.events ?? const Stream.empty();
});

// Derived convenience providers
final usersProvider = Provider<List<String>>(...);           // Online users (excludes self)
final sessionsProvider = Provider<Map<String, PeerSession>>(...);
final hasSessionProvider = Provider.family<bool, String>(...);
final connectionStatusProvider = Provider<ConnectionStatus>(...);
final isConnectedProvider = Provider<bool>(...);

// enrollment_provider.dart — Enrollment flow state
final enrollmentProvider = StateNotifierProvider<EnrollmentNotifier, EnrollmentStatus>(...);
// Phases: idle → scanning → passphrase → enrolling → complete/error

// messages_provider.dart — Conversation tracking
final conversationsProvider = StateNotifierProvider<ConversationsNotifier, List<Conversation>>(...);
final selectedPeerProvider = StateProvider<String?>(...);
```

### Navigation Flow

The app uses imperative screen routing in `CrypticApp` (a `ConsumerStatefulWidget`):

```
SplashScreen → checkAuthState()
  ├─ needsSetup → EnrollmentFlowScreen → LoginScreen
  └─ hasCerts   → LoginScreen
                      ↓ authenticate()
                   UsersScreen (home)
                      ↓ tap user
                   ChatScreen (Navigator.push)
```

`EnrollmentFlowScreen` internally switches between `QrScannerScreen`,
`PassphraseScreen`, and `EnrollmentProgressScreen` based on `EnrollmentPhase`.

### Chat Screen

```dart
class ChatScreen extends ConsumerWidget {
  final String peerUsername;
  
  const ChatScreen({required this.peerUsername});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(messagesProvider(peerUsername));
    final engineState = ref.watch(crypticEngineProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(peerUsername),
        subtitle: Text(engineState.connectionStatus),
        actions: [
          IconButton(
            icon: Icon(Icons.info),
            onPressed: () => _showContactInfo(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) => ListView.builder(
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return MessageBubble(
                    message: message,
                    isMe: message.from == engineState.username,
                  );
                },
              ),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
            ),
          ),
          MessageInputField(
            onSend: (text) {
              ref.read(crypticEngineProvider.notifier)
                  .sendMessage(peerUsername, text);
            },
          ),
        ],
      ),
    );
  }
}
```

## Key Flutter Packages

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  flutter_riverpod: ^2.4.0          # Reactive state management
  riverpod_annotation: ^2.3.0       # Riverpod code generation annotations
  
  # Cryptography
  pointycastle: ^3.9.0              # Ed25519, X25519, ChaCha20-Poly1305, Blake2b, ECDSA
  cryptography: ^2.7.0              # Argon2id KDF (used by enrollment)
  
  # Network
  web_socket_channel: ^2.4.0        # WebSocket client
  http: ^1.1.0                      # HTTP for enrollment REST endpoints
  
  # Storage
  flutter_secure_storage: ^9.0.0    # Secure key/cert storage (iOS Keychain)
  sqflite_sqlcipher: ^3.0.0         # Encrypted SQLite database (pending)
  path_provider: ^2.1.0             # File paths
  
  # Enrollment
  mobile_scanner: ^7.2.0            # QR code scanning (Apple Vision API on iOS)
  
  # Utilities
  uuid: ^4.2.0                      # Generate message IDs
  logger: ^2.0.0                    # Logging
  intl: ^0.18.0                     # Date formatting
  equatable: ^2.0.5                 # Value equality for models
  freezed_annotation: ^2.4.0        # Immutable data classes
  json_annotation: ^4.8.0           # JSON serialization
  cupertino_icons: ^1.0.6           # iOS-style icons
  
dev_dependencies:
  flutter_test:
    sdk: flutter
  
  # Code Generation
  build_runner: ^2.4.0              # Code generation runner
  freezed: ^2.4.0                   # Immutable data class generator
  json_serializable: ^6.7.0         # JSON serialization generator
  riverpod_generator: ^2.3.0        # Riverpod provider generator
  
  # Testing
  mockito: ^5.4.0                   # Mocking for tests
  mocktail: ^1.0.0                  # Lightweight mocking
  
  # Linting
  flutter_lints: ^3.0.0             # Lint rules
```

## Testing Strategy

### Unit Tests

```dart
// test/unit/crypto/x3dh_test.dart
void main() {
  group('X3DH Protocol', () {
    late X3DHEngine engine;
    
    setUp(() {
      engine = X3DHEngine();
    });
    
    test('should generate valid identity keys', () async {
      final keys = await engine.generateIdentityKeys();
      
      expect(keys.identitySignPublic.length, equals(32));
      expect(keys.identityDHPublic.length, equals(32));
      expect(keys.signedPrekeySignature.length, equals(64));
    });
    
    test('should perform X3DH key agreement', () async {
      // Alice (initiator)
      final aliceKeys = await engine.generateIdentityKeys();
      
      // Bob (responder)
      final bobKeys = await engine.generateIdentityKeys();
      final bobBundle = PrekeyBundle.from(bobKeys);
      
      // Alice performs X3DH
      final aliceResult = await engine.performX3DH(
        identityKeys: aliceKeys,
        peerBundle: bobBundle,
      );
      
      // Bob receives X3DH
      final bobResult = await engine.receiveX3DH(
        identityKeys: bobKeys,
        peerIdentityKey: aliceKeys.identityDHPublic,
        peerEphemeralKey: aliceResult.ephemeralPublic,
        usedOTPKId: null,
      );
      
      // Shared secrets should match
      expect(aliceResult.sharedKey, equals(bobResult.sharedKey));
    });
  });
}
```

### Integration Tests

```dart
// test/integration/message_flow_test.dart
void main() {
  testWidgets('should send and receive encrypted messages', (tester) async {
    // Initialize Alice's engine
    final alice = CrypticEngine(
      username: 'alice',
      crypto: MockCryptoRepository(),
      network: MockNetworkRepository(),
      storage: MockStorageRepository(),
    );
    await alice.initialize('password');
    
    // Initialize Bob's engine
    final bob = CrypticEngine(
      username: 'bob',
      crypto: MockCryptoRepository(),
      network: MockNetworkRepository(),
      storage: MockStorageRepository(),
    );
    await bob.initialize('password');
    
    // Alice sends message to Bob
    await alice.sendMessage('bob', 'Hello Bob!');
    
    // Wait for Bob to receive
    final message = await bob.messageStream.first;
    
    expect(message.from, equals('alice'));
    expect(message.text, equals('Hello Bob!'));
  });
}
```

## Security Considerations

1. **Key Storage**: Uses `flutter_secure_storage` backed by iOS Keychain / Android Keystore
2. **Certificate Storage**: mTLS client cert/key/CA stored in iOS Keychain
3. **Database Encryption**: `sqflite_sqlcipher` available for message DB (not yet wired)
4. **Forward Secrecy**: Double Ratchet with DH ratchet steps
5. **CA Fingerprint Pinning**: Enrollment verifies CA certificate SHA-256 fingerprint from QR payload
6. **Enrollment Security**: One-time Ed25519 key consumed on use; Argon2id-encrypted QR envelope
7. **Memory Security**: Clear sensitive data from memory after use
8. **Code Obfuscation**: Enable ProGuard/R8 for Android release builds
9. **Root Detection**: Detect jailbroken/rooted devices and warn users (planned)

## Implementation Progress

### Completed Phases

1. ✅ **Phase 1**: Crypto primitives (X3DH, Double Ratchet)
   - Ed25519 signing, X25519 key exchange
   - ChaCha20-Poly1305 AEAD encryption
   - Blake2b KDF (matching libsodium's `crypto_kdf_derive_from_key`)
   - XOR-based root key mixing for ratchet

2. ✅ **Phase 2**: WebSocket client with mTLS
   - Certificate-based authentication
   - Connection state management
   - ConnectionManager with reconnect/heartbeat (available but engine uses raw WebSocketClient)

3. ✅ **Phase 3**: Storage layer (keys, sessions, certificates)
   - Secure key storage via flutter_secure_storage (iOS Keychain)
   - Session state persistence (per-peer ratchet state)
   - Certificate storage for mTLS material
   - Message database (SQLCipher) - dependency present, not wired

4. ✅ **Phase 4**: CrypticEngine orchestration
   - Event-driven architecture with streams (EngineEvent hierarchy)
   - Pending message queue for X3DH key bundle retrieval
   - Session management per peer via SessionManager
   - MessageProcessor for inbound message routing

5. ✅ **Phase 5**: UI screens (core functionality)
   - Login screen with passphrase
   - Users list with online status
   - Chat screen with message bubbles
   - Connection status indicator
   - Enrollment flow (QR → passphrase → progress)

6. ✅ **Phase 6**: Mobile enrollment (M8)
   - QR code scanning (mobile_scanner v7 / Apple Vision API)
   - Argon2id + AES-256-CBC payload decryption
   - ECDSA P-256 keypair + PKCS#10 CSR generation (PointyCastle)
   - Ed25519 CSR signature for server authentication
   - CA certificate fetch with SHA-256 fingerprint pinning
   - mTLS certificate storage in iOS Keychain

### Remaining Work

7. 🔄 **Phase 7**: Polish and extended features
   - Message persistence to SQLCipher database
   - Certificate renewal flow
   - Push notifications
   - Settings screen
   - Contact management
   - Key verification UI

8. 📋 **Phase 8**: Testing and deployment
   - Expand unit test coverage
   - Integration tests
   - Security audit
   - App store / F-Droid deployment

## Critical Implementation Details

### KDF Implementation (Blake2b)

The Erlang server uses libsodium's `crypto_kdf_derive_from_key` which is Blake2b-based.
This was the most critical discovery for interoperability:

```dart
// lib/data/crypto/primitives/kdf_service.dart
// Must match libsodium's crypto_kdf_derive_from_key exactly

Uint8List deriveKey({
  required int length,      // Output key length (32 bytes)
  required int subkeyId,    // Subkey identifier (8-byte LE integer)
  required String context,  // 8-character context string
  required Uint8List key,   // 32-byte master key
}) {
  // Salt = subkeyId as 8-byte little-endian + 8 bytes of zeros
  final salt = Uint8List(16);
  for (int i = 0; i < 8; i++) {
    salt[i] = (subkeyId >> (i * 8)) & 0xFF;
  }
  
  // Personalization = context (8 chars) + 8 bytes of zeros
  final personal = Uint8List(16);
  final contextBytes = utf8.encode(context.padRight(8).substring(0, 8));
  personal.setAll(0, contextBytes);
  
  // Blake2b with salt and personalization
  final blake2b = Blake2bDigest(
    digestSize: length,
    salt: salt,
    personalization: personal,
  );
  blake2b.update(key, 0, key.length);
  // ...
}
```

### Double Ratchet Key Derivation

The ratchet uses XOR mixing (not HKDF) for root key updates:

```dart
// Root key update uses XOR, not HKDF
Uint8List _mixKeys(Uint8List rootKey, Uint8List dhOutput) {
  final mixed = Uint8List(32);
  for (int i = 0; i < 32; i++) {
    mixed[i] = rootKey[i] ^ dhOutput[i];
  }
  return mixed;
}

// Then derive chain keys from mixed key
(newRootKey, initChainKey, respChainKey) = _kdfService.deriveRatchetKeys(mixedKey);
```

### Chain Key Selection (Critical for Interop)

The chain key selection depends on role and operation:

```dart
// On RECEIVE (after DH ratchet):
//   - Use RespChainKey for receiving current message
//   - Store InitChainKey for future sending
newState = state.copyWith(
  sendChainKey: initChainKey,   // For future sends
  recvChainKey: respChainKey,   // For current receive
);

// On SEND (after receiving):
//   - Use RespChainKey for sending
newState = state.copyWith(
  sendChainKey: respChainKey,   // For current send
);
```

This matches the Erlang implementation in `cryptic_double_ratchet.erl`:
- Initiator (Alice): Uses `init` chain for sending, `resp` chain for receiving
- Responder (Bob): Uses `resp` chain for sending after first receive

### Protocol Message Field Names

The server uses specific field names that must match exactly:

| Client Sends | Server Expects |
|--------------|----------------|
| `from` | ✓ (not `from_user`) |
| `to` | ✓ (not `to_user`) |
| `ephemeral_public` | ✓ (not `ephemeral_key`) |
| `otpk_id` | ✓ (not `one_time_prekey_id`) |
| `dh_step` | ✓ (must be included) |
| `prev_chain_length` | ✓ (not `previous_chain_length`) |
| `msg_number` | ✓ (not `message_number`) |

## UI Layout Design

### Design Philosophy

The Cryptic mobile app should prioritize:
1. **Simplicity**: Clean, uncluttered interface focusing on secure messaging
2. **Privacy First**: Minimal metadata display, no read receipts by default
3. **Security Visibility**: Clear indicators of encryption status and connection security
4. **Offline Support**: Queue messages when offline, show sync status
5. **Dark Theme Default**: Reduce eye strain and battery usage

### Main Navigation Structure

```
┌─────────────────────────────────────────────────────┐
│  Bottom Navigation Bar (3 tabs)                     │
│  ┌────────┬────────┬────────┐                       │
│  │ Chats  │ People │Settings│                       │
│  └────────┴────────┴────────┘                       │
└─────────────────────────────────────────────────────┘
```

### Screen 1: Chats List (Home)

```
┌─────────────────────────────────────────────────────┐
│ ┌─────┐ Cryptic          🔒 Encrypted    [⚙️]        │ AppBar
│ │ 🔐  │                  🟢 Connected                │
│ └─────┘                                             │
├─────────────────────────────────────────────────────┤
│ 🔍 Search conversations...                         │ Search
├─────────────────────────────────────────────────────┤
│ ┌─────┐ Alice                              14:23    │
│ │  A  │ Hey, did you see that?              [2]     │ Chat Item
│ └─────┘ ●●● Typing...                               │ (3 unread)
├─────────────────────────────────────────────────────┤
│ ┌─────┐ Bob                                09:15    │
│ │  B  │ Meeting at 3pm                      ✓✓      │ Chat Item
│ └─────┘                                             │ (read)
├─────────────────────────────────────────────────────┤
│ ┌─────┐ Charlie                        Yesterday    │
│ │  C  │ Thanks for the help!                ✓       │ Chat Item
│ └─────┘                                             │ (delivered)
├─────────────────────────────────────────────────────┤
│ ┌─────┐ Diana                          2 days ago   │
│ │  D  │ 🔄 Establishing secure session...           │ Chat Item
│ └─────┘                                             │ (X3DH in progress)
├─────────────────────────────────────────────────────┤
│                                                     │
│              Empty State:                           │
│        "No conversations yet"                       │
│        "Tap + to start chatting"                    │
│                                                     │
└─────────────────────────────────────────────────────┘
│ 🏠 Chats    👥 People    ⚙️ Settings              │ Bottom Nav
└─────────────────────────────────────────────────────┘

                    [+]  Floating Action Button
```

**Features:**
- Avatar with first letter of username (no photos for privacy)
- Connection status indicator (🟢 connected, 🔴 offline, 🟡 reconnecting)
- Encryption status (🔒 encrypted, 🔓 establishing session)
- Message preview (truncated, no sensitive data in notifications)
- Timestamp (smart formatting: time, yesterday, date)
- Delivery status: ✓ sent, ✓✓ delivered (no read receipts for privacy)
- Unread badge count
- Typing indicator when peer is typing
- Swipe actions: Archive, Delete, Pin

### Screen 2: Chat Conversation

```
┌─────────────────────────────────────────────────────┐
│ ← Alice                    🔒 E2EE         [⋮]       │ AppBar
│                         Last seen: Never            │ (Privacy)
├─────────────────────────────────────────────────────┤
│                        [ℹ️ System Notice]           │
│         Session established with Alice              │ System
│         Encryption: Double Ratchet + X3DH           │ Message
│         Fingerprint: F479...DFFF                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────┐           │
│  │ Hey! How are you doing?              │  14:20    │ Their
│  │                                      │     ✓     │ Message
│  └──────────────────────────────────────┘           │
│                                                     │
│                   ┌────────────────────────────┐    │
│            14:23  │ I'm good, thanks!          │    │ Your
│               ✓✓  │ How about you?             │    │ Message
│                   └────────────────────────────┘    │
│                                                     │
│  ┌──────────────────────────────────────┐           │
│  │ Pretty good. Want to grab coffee?    │  14:25    │ Their
│  │                                      │     ✓     │ Message
│  └──────────────────────────────────────┘           │
│                                                     │
│                   ┌────────────────────────────┐    │
│            14:27  │ Sure! When?                │    │ Your
│               🔄  │                            │    │ Message
│                   └────────────────────────────┘    │ (Sending)
│                                                     │
│  ●●● Alice is typing...                             │ Typing
│                                                     │ Indicator
├─────────────────────────────────────────────────────┤
│ [📎] ┌────────────────────────────────┐  [🎤] [📷]   │ Input
│      │ Type a message...              │             │ Toolbar
│      └────────────────────────────────┘      [➤]    │
└─────────────────────────────────────────────────────┘
```

**Features:**
- Message bubbles (theirs left, yours right)
- Timestamp on each message
- Delivery status on your messages
- System messages for key events (session established, key rotated)
- Typing indicator
- Long-press for actions: Copy, Delete, Reply
- Swipe up/down to scroll through history
- Pull down to load older messages
- "Jump to bottom" button when scrolled up
- Input toolbar with:
  - Attachment button (files, not media for privacy)
  - Voice memo button (encrypted audio)
  - Camera button (for sending encrypted photos)
  - Send button

### Screen 3: People (Contacts)

```
┌─────────────────────────────────────────────────────┐
│ People                                      [+]     │ AppBar
│                                                     │
├─────────────────────────────────────────────────────┤
│ 🔍 Search by username...                            │ Search
├─────────────────────────────────────────────────────┤
│ Active Contacts (5)                                 │ Section
├─────────────────────────────────────────────────────┤
│ ┌─────┐ Alice                    🟢 Online          │
│ │  A  │ Last seen: Active now                      │ Contact
│ └─────┘ Fingerprint: F479...DFFF              [💬]  │ Item
├─────────────────────────────────────────────────────┤
│ ┌─────┐ Bob                      🟡 Away            │
│ │  B  │ Last seen: 5 mins ago                      │ Contact
│ └─────┘ Fingerprint: A123...BC45              [💬]  │ Item
├─────────────────────────────────────────────────────┤
│ All Users on Server (12)                            │ Section
├─────────────────────────────────────────────────────┤
│ ┌─────┐ Charlie                  🔴 Offline         │
│ │  C  │ Never contacted                             │ Contact
│ └─────┘ Fingerprint: Not established          [💬]  │ Item
├─────────────────────────────────────────────────────┤
│ ┌─────┐ Diana                                       │
│ │  D  │ Never contacted                             │ Contact
│ └─────┘ Fingerprint: Not established          [💬]  │ Item
├─────────────────────────────────────────────────────┤
│                                                     │
└─────────────────────────────────────────────────────┘
│ 🏠 Chats    👥 People    ⚙️ Settings                 │ Bottom Nav
└─────────────────────────────────────────────────────┘
```

**Features:**
- List all registered users on server
- Show online/offline status (if enabled on server)
- Group into "Active Contacts" (have exchanged messages) and "All Users"
- Show key fingerprint once session established
- Tap to view details
- Tap 💬 to start conversation
- Search/filter by username
- Pull to refresh user list from server

### Screen 4: Contact Detail

```
┌─────────────────────────────────────────────────────┐
│ ← Contact Info                                      │ AppBar
│                                                     │
├─────────────────────────────────────────────────────┤
│           ┌─────────────┐                           │
│           │             │                           │
│           │      A      │  Large Avatar             │
│           │             │                           │
│           └─────────────┘                           │
│                                                     │
│              Alice                                  │ Username
│         alice@cryptic                               │
│                                                     │
│      [🔐 Verify Keys]  [💬 Message]                  │ Actions
│                                                     │
├─────────────────────────────────────────────────────┤
│ Security Information                                │
├─────────────────────────────────────────────────────┤
│ 🔒 Session Status                                   │
│    Active - Double Ratchet Encryption               │
│                                                     │
│ 🔑 Identity Key Fingerprint                         │
│    F479 A1EB AAAD FFF4 3B2C                         │
│    91DE 8A73 BB19 CD45 E8F2                         │
│    [Copy] [QR Code] [Verify in Person]              │
│                                                     │
│ 📊 Session Statistics                               │
│    Messages exchanged: 127                          │
│    Session created: 2 days ago                      │
│    Last message: 5 mins ago                         │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Conversation Settings                               │
├─────────────────────────────────────────────────────┤
│ 🔔 Notifications              [Toggle: ON]          │
│ 📌 Pin conversation            [Toggle: OFF]        │
│ 🗄️ Archive                                          │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Danger Zone                                         │
├─────────────────────────────────────────────────────┤
│ 🔄 Reset Session (New Keys)                         │
│ 🗑️ Delete Conversation                              │
│ 🚫 Block User                                       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Features:**
- Display key fingerprint prominently
- QR code for in-person verification
- Session statistics
- Conversation management
- Security actions (reset session, verify keys)

### Screen 5: Settings

```
┌─────────────────────────────────────────────────────┐
│ Settings                                            │ AppBar
│                                                     │
├─────────────────────────────────────────────────────┤
│ Account                                             │ Section
├─────────────────────────────────────────────────────┤
│ ┌─────┐ admin                                       │
│ │  @  │ Logged in                                   │ Profile
│ └─────┘ admin@cryptic.local                         │
│         [Change Passphrase]                         │
├─────────────────────────────────────────────────────┤
│ Connection                                          │ Section
├─────────────────────────────────────────────────────┤
│ 🌐 Server: localhost:8443                           │
│    Status: 🟢 Connected                             │
│    [Change Server] [Test Connection]                │
│                                                     │
│ 🔐 Certificate Status                               │
│    Valid until: Dec 31, 2025                        │
│    Fingerprint: A1B2...C3D4                         │
│    [View Details] [Renew]                           │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Security                                            │ Section
├─────────────────────────────────────────────────────┤
│ 🔑 My Identity Key                                  │
│    Fingerprint: F479 A1EB AAAD FFF4...              │
│    [View Full Key] [Export Backup]                  │
│                                                     │
│ 🗄️ Message History                                  │
│    Database: Encrypted                              │
│    Size: 12.4 MB                                    │
│    [Export] [Clear All]                             │
│                                                     │
│ 🔒 Screen Lock                   [Toggle: ON]       │
│    Require passphrase on app start                  │
│                                                     │
│ 📱 Biometric Unlock             [Toggle: OFF]       │
│    Use fingerprint/face to unlock                   │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Privacy                                             │ Section
├─────────────────────────────────────────────────────┤
│ 👁️ Read Receipts                 [Toggle: OFF]      │
│    Let others know when you read messages           │
│                                                     │
│ ✍️ Typing Indicators            [Toggle: ON]        │
│    Show when you're typing                          │
│                                                     │
│ 🕐 Last Seen                     [Toggle: OFF]      │
│    Share your last active time                      │
│                                                     │
│ 📸 Save Media to Gallery         [Toggle: OFF]      │
│    Automatically save received photos               │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Appearance                                          │ Section
├─────────────────────────────────────────────────────┤
│ 🎨 Theme                        [Dark]              │
│    Options: Light, Dark, System                     │
│                                                     │
│ 💬 Message Text Size            [Medium]            │
│    Options: Small, Medium, Large                    │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Data & Storage                                      │ Section
├─────────────────────────────────────────────────────┤
│ 💾 Storage Usage: 45.2 MB                           │
│    Messages: 12.4 MB                                │
│    Keys/Sessions: 2.1 MB                            │
│    Cache: 30.7 MB                                   │
│    [Clear Cache]                                    │
│                                                     │
├─────────────────────────────────────────────────────┤
│ About                                               │ Section
├─────────────────────────────────────────────────────┤
│ ℹ️ Version: 1.0.0 (Build 42)                        │
│ 📚 Documentation                                    │
│ 🐛 Report Bug                                       │
│ 📜 Open Source Licenses                             │
│ 🔐 Security Audit Report                            │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Danger Zone                                         │ Section
├─────────────────────────────────────────────────────┤
│ 🗑️ Delete All Data                                  │
│    Remove all messages, keys, and settings          │
│                                                     │
│ 🚪 Log Out                                          │
│    Disconnect and clear session                     │
│                                                     │
└─────────────────────────────────────────────────────┘
│ 🏠 Chats    👥 People    ⚙️ Settings              │ Bottom Nav
└─────────────────────────────────────────────────────┘
```

**Features:**
- Comprehensive settings organization
- Clear security indicators
- Easy access to key management
- Privacy controls
- Connection management
- Theme customization

### Color Scheme (Dark Theme)

```dart
// lib/core/theme/app_colors.dart
class AppColors {
  // Primary Colors
  static const primary = Color(0xFF4A90E2);      // Blue for trust
  static const secondary = Color(0xFF50C878);    // Green for security
  static const accent = Color(0xFFE94B3C);       // Red for warnings
  
  // Background
  static const background = Color(0xFF121212);   // Near black
  static const surface = Color(0xFF1E1E1E);      // Slightly lighter
  static const card = Color(0xFF2C2C2C);         // Cards/bubbles
  
  // Text
  static const textPrimary = Color(0xFFE0E0E0); // Light gray
  static const textSecondary = Color(0xFF9E9E9E); // Muted gray
  static const textHint = Color(0xFF616161);     // Darker gray
  
  // Status
  static const online = Color(0xFF4CAF50);       // Green
  static const offline = Color(0xFFBDBDBD);      // Gray
  static const away = Color(0xFFFFA726);         // Orange
  
  // Message Bubbles
  static const ownMessageBubble = Color(0xFF2C5F8D);    // Dark blue
  static const otherMessageBubble = Color(0xFF3A3A3A);  // Dark gray
  
  // Security
  static const encrypted = Color(0xFF4CAF50);    // Green lock
  static const unencrypted = Color(0xFFFF9800);  // Orange warning
}
```

### Typography

```dart
// lib/core/theme/app_text_styles.dart
class AppTextStyles {
  static const headline1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  
  static const headline2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  
  static const bodyLarge = TextStyle(
    fontSize: 16,
    color: AppColors.textPrimary,
  );
  
  static const bodyMedium = TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
  );
  
  static const caption = TextStyle(
    fontSize: 12,
    color: AppColors.textHint,
  );
  
  static const messageText = TextStyle(
    fontSize: 15,
    height: 1.4,
    color: AppColors.textPrimary,
  );
}
```

## Alternative Distribution Methods (Non-Store Deployment)

For privacy-focused users who want to avoid Google Play Store or
Apple App Store, here are low-key deployment options:

### 1. Direct APK Distribution (Android)

**Advantages:**
- No Google account required
- No app store approval process
- Complete control over updates
- Works on de-Googled phones (GrapheneOS, CalyxOS, LineageOS)
- Immediate deployment

**Implementation:**

#### Step 1: Build Release APK

```bash
# Build release APK with split ABIs for smaller size
flutter build apk --release --split-per-abi

# Output files (in build/app/outputs/flutter-apk/):
# - app-armeabi-v7a-release.apk  (32-bit ARM, ~20MB)
# - app-arm64-v8a-release.apk    (64-bit ARM, ~25MB) - Most phones
# - app-x86_64-release.apk       (64-bit Intel, for emulators)
```

#### Step 2: Sign APK (Required for Installation)

```bash
# Generate signing key (one time)
keytool -genkey -v -keystore cryptic-release-key.jks \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias cryptic-key

# Configure in android/key.properties:
storePassword=<your-password>
keyPassword=<your-password>
keyAlias=cryptic-key
storeFile=/path/to/cryptic-release-key.jks

# Build will automatically sign
flutter build apk --release
```

#### Step 3: Distribute APK

**Option A: Self-Hosted Website**

```nginx
# nginx config for APK hosting
server {
    listen 443 ssl;
    server_name downloads.cryptic.app;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    root /var/www/cryptic/apk;
    
    location /latest {
        alias /var/www/cryptic/apk/app-arm64-v8a-release.apk;
        add_header Content-Disposition 'attachment; filename="cryptic-latest.apk"';
        add_header Content-Type "application/vnd.android.package-archive";
    }
    
    location /verify {
        alias /var/www/cryptic/apk/checksums.txt;
        add_header Content-Type "text/plain";
    }
}
```

Provide checksums for verification:
```bash
# Generate checksums
sha256sum *.apk > checksums.txt
gpg --clearsign checksums.txt

# Users verify:
wget https://downloads.cryptic.app/latest
wget https://downloads.cryptic.app/checksums.txt.asc
gpg --verify checksums.txt.asc
sha256sum -c checksums.txt
```

**Option B: IPFS (Decentralized)**

```bash
# Add APK to IPFS
ipfs add app-arm64-v8a-release.apk
# Returns: QmXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Share IPFS CID (Content Identifier)
# Users download with:
ipfs get QmXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# or via gateway:
https://ipfs.io/ipfs/QmXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Option C: Tor Hidden Service**

```
# /etc/tor/torrc
HiddenServiceDir /var/lib/tor/cryptic_downloads/
HiddenServicePort 80 127.0.0.1:8080

# Restart tor to get .onion address
# Share: http://abc123xyz.onion/cryptic-latest.apk
```

**Option D: Direct File Sharing**

- Email attachment (for trusted contacts)
- Encrypted cloud storage (ProtonDrive, MEGA)
- Syncthing (peer-to-peer sync)
- Physical transfer (USB, NFC)

#### Step 4: User Installation Instructions

**For Users:**

1. **Enable installation from unknown sources:**
   ```
   Settings → Security → Install unknown apps
   → [Your Browser/File Manager] → Allow
   ```

2. **Download APK** from trusted source

3. **Verify checksum:**
   ```bash
   # Using Termux on Android
   pkg install coreutils
   sha256sum cryptic-latest.apk
   # Compare with published checksum
   ```

4. **Install:**
   - Tap downloaded APK file
   - Android will show permissions required
   - Tap "Install"
   - Grant necessary permissions (storage, network)

5. **First run:**
   - App will prompt for passphrase
   - Generate or import identity keys
   - Configure server connection

### 2. F-Droid Repository (Android - Open Source Distribution)

**Advantages:**
- Trusted by privacy-conscious users
- Automatic updates
- Reproducible builds (verifiable)
- No Google required
- Free and open source only

**Requirements:**
- App must be 100% open source
- No proprietary libraries
- No tracking/analytics
- Source code publicly available

**Setup:**

#### Create F-Droid Repository

```bash
# 1. Install fdroidserver
pip install fdroidserver

# 2. Initialize repository
mkdir -p fdroid-repo/{metadata,repo}
cd fdroid-repo
fdroid init

# 3. Configure repository
cat > config.yml <<EOF
repo_name: "Cryptic Messenger"
repo_description: "End-to-end encrypted messaging"
repo_url: "https://fdroid.cryptic.app/repo"
archive_url: "https://fdroid.cryptic.app/archive"
repo_icon: "icon.png"
repo_keyalias: "cryptic-fdroid"
EOF

# 4. Create app metadata
cat > metadata/com.cryptic.messenger.yml <<EOF
Categories:
  - Internet
  - Security
License: MIT
AuthorName: Cryptic Team
AuthorEmail: dev@cryptic.app
SourceCode: https://github.com/etnt/cryptic
IssueTracker: https://github.com/etnt/cryptic/issues

AutoName: Cryptic Messenger
Summary: End-to-end encrypted messaging
Description: |
  Cryptic is a privacy-focused messenger using Signal Protocol.
  Features:
  * X3DH key agreement
  * Double Ratchet encryption
  * mTLS server connection
  * No phone number required
  * No central identity server
  * Offline message queueing

RepoType: git
Repo: https://github.com/etnt/cryptic

Builds:
  - versionName: '1.0.0'
    versionCode: 1
    commit: v1.0.0
    subdir: flutter-app
    output: build/app/outputs/flutter-apk/app-release.apk
    build:
      - flutter build apk --release
    ndk: r21e
EOF

# 5. Build and publish
fdroid update
fdroid publish

# 6. Upload to web server
rsync -avz repo/ user@fdroid.cryptic.app:/var/www/fdroid/
```

#### Users Add Repository

```
F-Droid → Settings → Repositories → Add Repository
URL: https://fdroid.cryptic.app/repo
Fingerprint: <your-repo-fingerprint>
```

### 3. iOS Distribution (Without App Store)

**Option A: TestFlight (Limited to 10,000 testers)**

```bash
# 1. Build for TestFlight
flutter build ipa --release

# 2. Upload via Xcode or Transporter
# 3. Share TestFlight link with testers
# Link expires after 90 days per build
```

**Option B: Ad Hoc Distribution (100 devices max)**

```bash
# 1. Register device UDIDs in Apple Developer Portal
# 2. Create Ad Hoc provisioning profile
# 3. Build with profile
flutter build ipa --export-options-plist=AdHoc.plist

# 4. Distribute IPA via:
#    - Apple Configurator 2
#    - iTunes File Sharing
#    - Direct URL (install via Safari)
```

**Option C: Enterprise Distribution (Requires Apple Enterprise Account)**

```bash
# For in-house distribution only
# Not allowed for public distribution
# Risk of certificate revocation if abused
```

**Option D: Jailbroken Devices (Not Recommended)**

- Install via Cydia/Sileo
- No signing required
- Security implications for users

### 4. Progressive Web App (PWA) - Cross-Platform Alternative

**Advantages:**
- No app store required
- Works on iOS and Android
- Automatic updates
- Single codebase
- No installation required (initially)

**Limitations:**
- Limited cryptographic API access (no secure enclave)
- No background sync (must be open)
- No push notifications on iOS
- Can't access certain device features

**Implementation:**

```dart
// Build Flutter PWA
flutter build web --release

// Deploy to web server
rsync -avz build/web/ user@app.cryptic.io:/var/www/html/

// Users access via browser:
https://app.cryptic.io

// Add to home screen prompt appears
```

**manifest.json for PWA:**
```json
{
  "name": "Cryptic Messenger",
  "short_name": "Cryptic",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#121212",
  "theme_color": "#4A90E2",
  "description": "End-to-end encrypted messaging",
  "icons": [
    {
      "src": "icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
```

### 5. Update Mechanism (Without App Stores)

Since you're not using app stores, implement your own update system:

#### In-App Update Checker

```dart
class UpdateChecker {
  static const updateCheckUrl = 'https://api.cryptic.app/version';
  
  Future<UpdateInfo?> checkForUpdates() async {
    try {
      final response = await http.get(Uri.parse(updateCheckUrl));
      final data = jsonDecode(response.body);
      
      final latestVersion = data['version'];
      final currentVersion = await getPackageVersion();
      
      if (_isNewerVersion(latestVersion, currentVersion)) {
        return UpdateInfo(
          version: latestVersion,
          downloadUrl: data['download_url'],
          releaseNotes: data['release_notes'],
          signature: data['signature'],  // GPG signature
          checksum: data['sha256'],
        );
      }
      
      return null;
    } catch (e) {
      print('Update check failed: $e');
      return null;
    }
  }
  
  Future<void> downloadAndInstall(UpdateInfo info) async {
    // 1. Download APK
    final file = await _downloadFile(info.downloadUrl);
    
    // 2. Verify signature
    final isValid = await _verifySignature(file, info.signature);
    if (!isValid) {
      throw Exception('Invalid signature - update rejected');
    }
    
    // 3. Verify checksum
    final checksum = await _calculateChecksum(file);
    if (checksum != info.checksum) {
      throw Exception('Checksum mismatch - update rejected');
    }
    
    // 4. Install (Android only)
    if (Platform.isAndroid) {
      await InstallPlugin.installApk(file.path);
    } else {
      // iOS: Open Safari to TestFlight or show instructions
      await launchUrl(info.downloadUrl);
    }
  }
  
  bool _isNewerVersion(String latest, String current) {
    final latestParts = latest.split('.').map(int.parse).toList();
    final currentParts = current.split('.').map(int.parse).toList();
    
    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }
}
```

#### Version API Endpoint

```json
// https://api.cryptic.app/version
{
  "version": "1.0.1",
  "build": 43,
  "release_date": "2025-11-18",
  "download_url": "https://downloads.cryptic.app/v1.0.1/app-arm64-v8a-release.apk",
  "sha256": "abc123...",
  "signature": "-----BEGIN PGP SIGNATURE-----\n...\n-----END PGP SIGNATURE-----",
  "release_notes": "- Fixed connection issue\n- Improved message sync",
  "minimum_version": "1.0.0",
  "force_update": false
}
```

### 6. Distribution Comparison

| Method | Android | iOS | Store Approval | Auto-Updates | User Trust | Privacy |
|--------|---------|-----|----------------|--------------|------------|---------|
| Direct APK | ✅ | ❌ | No | Manual | Low | High |
| F-Droid | ✅ | ❌ | Yes (OSS) | Yes | High | High |
| Self-hosted | ✅ | Limited | No | Custom | Medium | High |
| IPFS | ✅ | ❌ | No | Manual | Medium | Very High |
| TestFlight | ❌ | ✅ | Yes | Yes | High | Medium |
| PWA | ✅ | ✅ | No | Automatic | Medium | Medium |
| Play Store | ✅ | ❌ | Yes | Yes | Very High | Low |
| App Store | ❌ | ✅ | Yes | Yes | Very High | Low |

### 7. Recommended Distribution Strategy

**For Maximum Privacy and Control:**

1. **Primary:** Self-hosted APK with GPG signatures
   - Full control
   - No third-party tracking
   - Verifiable downloads

2. **Alternative:** F-Droid repository
   - Trusted by privacy community
   - Reproducible builds
   - Automatic updates

3. **Fallback:** IPFS for censorship resistance
   - Decentralized
   - No takedowns possible
   - Global availability

4. **Web Access:** PWA for quick access
   - No installation required
   - Works everywhere
   - Limited features but functional

**Distribution Workflow:**

```bash
# Release script
#!/bin/bash

VERSION="1.0.1"

# 1. Build APK
flutter build apk --release --split-per-abi

# 2. Sign and verify
jarsigner -verify app-arm64-v8a-release.apk

# 3. Generate checksums
sha256sum *.apk > checksums.txt

# 4. Sign checksums with GPG
gpg --clearsign checksums.txt

# 5. Upload to self-hosted server
scp *.apk checksums.txt.asc user@downloads.cryptic.app:/var/www/apk/v${VERSION}/

# 6. Update version API
curl -X POST https://api.cryptic.app/update-version \
  -H "Authorization: Bearer $API_TOKEN" \
  -d "{\"version\": \"${VERSION}\", \"url\": \"https://downloads.cryptic.app/v${VERSION}/\"}"

# 7. Add to IPFS
ipfs add -r v${VERSION}/ | tee ipfs-cids.txt

# 8. Update F-Droid metadata
cd fdroid-repo
git tag v${VERSION}
fdroid update
fdroid publish

# 9. Announce release
echo "Release ${VERSION} complete!"
echo "APK: https://downloads.cryptic.app/v${VERSION}/"
echo "IPFS: $(cat ipfs-cids.txt | grep 'added' | tail -1 | awk '{print $2}')"
```

## Mobile Enrollment Architecture

Mobile devices are onboarded without GPG via a QR-code-based Ed25519 enrollment
flow. See [Mobile Enrollment Plan](MOBILE-ENROLLMENT-PLAN.md) for the full
protocol specification.

### Enrollment Flow

```
Admin (cryptic-onboard)          Server                    Mobile App
─────────────────────────       ────────                  ──────────
Generate Ed25519 keypair
   │
   ├─ POST /ca/v1/admin/       Register enrollment
   │  register-enrollment  ──▶  identity (pub key)
   │
   ├─ Encrypt payload with
   │  Argon2id + AES-256-CBC
   │
   └─ Generate QR code          ◀── Hand QR to user ──▶  Scan QR
                                                          │
                                                     Enter passphrase
                                                          │
                                                     Decrypt payload
                                                          │
                                                     Verify CA cert
                                                          │
                                                     Generate ECDSA P-256
                                                     keypair + CSR
                                                          │
                                                     Sign CSR with Ed25519
                                                          │
                                                     POST /ca/v1/     Issue cert,
                                                     mobile-csr  ──▶  mark consumed
                                                          │
                                                     Store cert + key
                                                          │
                                                     Connect WebSocket
```

### Server Endpoints (Enrollment)

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `POST /ca/v1/admin/register-enrollment` | mTLS (admin) | Register Ed25519 public key |
| `POST /ca/v1/mobile-csr` | Ed25519 signature | Submit CSR, receive certificate |
| `GET /ca/v1/ca-cert` | None | Download CA certificate |

### Key Files

| Layer | File | Purpose |
|-------|------|---------|
| **Server** | `cryptic_ca_mobile_handler.erl` | Mobile CSR endpoint |
| **Server** | `cryptic_ca_admin_handler.erl` | Admin enrollment registration |
| **Server** | `cryptic_ca_store.erl` | Enrollment identity CRUD |
| **Tooling** | `bin/cryptic-onboard` | `create-mobile-enrollment` command |
| **Mobile** | `lib/data/enrollment/enrollment_service.dart` | Enrollment orchestrator |
| **Mobile** | `lib/data/enrollment/enrollment_crypto.dart` | QR decryption + Ed25519 signing |
| **Mobile** | `lib/data/enrollment/csr_generator.dart` | ECDSA P-256 keypair + PKCS#10 CSR |
| **Mobile** | `lib/presentation/screens/enrollment/` | UI screens |

## References

- [Signal Protocol Specifications](https://signal.org/docs/)
- [Flutter Cryptography Guide](https://pub.dev/packages/cryptography)
- [PointyCastle Documentation](https://pub.dev/packages/pointycastle)
- [Riverpod State Management](https://riverpod.dev/)
- [F-Droid Build Documentation](https://f-droid.org/docs/Building_Applications/)
- [Android APK Signing](https://developer.android.com/studio/publish/app-signing)
- [Flutter PWA Guide](https://docs.flutter.dev/platform-integration/web/building)
- [IPFS Documentation](https://docs.ipfs.tech/)
