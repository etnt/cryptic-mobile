# AGENTS.md - Cryptic System Architecture for AI Assistants

> **Purpose**: This document provides a comprehensive overview of the Cryptic
messaging system architecture, specifically designed to quickly onboard AI
assistants working on new interfaces, like a Rust-based Ratatui terminal UI
or a mobile phone UI.

## Table of Contents
1. [System Overview](#system-overview)
2. [Event Bus Architecture](#event-bus-architecture)
3. [Message Flow & Components](#message-flow--components)
4. [Event Types & Payloads](#event-types--payloads)
5. [WebSocket Protocol](#websocket-protocol)
6. [Cryptographic Engine](#cryptographic-engine)
7. [Storage Systems](#storage-systems)
8. [Flutter Mobile App Architecture](#flutter-mobile-app-architecture)
9. [Building a New UI Client](#building-a-new-ui-client)
10. [Reference Implementation](#reference-implementation)

---

## System Overview

**Cryptic** is an end-to-end encrypted messaging system built in Erlang/OTP that implements:
- **X3DH** (Extended Triple Diffie-Hellman) for initial key agreement
- **Double Ratchet** protocol for ongoing message encryption with forward secrecy
- **WebSocket mTLS** for real-time client-server communication
- **Event-driven architecture** with publish/subscribe pattern

### Key Architectural Principles
1. **Separation of Concerns**: Engine (crypto) ↔ Event Bus (messaging) ↔ UI (display)
2. **Callback-Based Design**: UIs implement `cryptic_engine` behavior callbacks
3. **Event-Driven Communication**: All components communicate via `cryptic_event_bus`
4. **Transport Agnostic**: Crypto engine doesn't know about WebSocket details

---

## Event Bus Architecture

### Core Component: `cryptic_event_bus`

The event bus is a lightweight OTP `gen_server` that provides pub/sub functionality for all system components. It's the **central nervous system** of Cryptic.

**Location**: `src/cryptic_event_bus.erl`

### Key Features
- **Asynchronous event publishing** (non-blocking cast operations)
- **Filter-based subscriptions** (subscribers can filter which events they receive)
- **Automatic cleanup** of dead subscribers via process monitoring
- **Topic-based subscriptions** for room/channel functionality
- **Safe error handling** (filter crashes don't affect other subscribers)

### API Quick Reference

```erlang
%% Start the event bus (typically started by supervisor)
{ok, Pid} = cryptic_event_bus:start_link().

%% Subscribe to all events
cryptic_event_bus:subscribe(self()).

%% Subscribe with filter (only specific event types)
Filter = fun(#{type := websocket_message}) -> true; (_) -> false end,
cryptic_event_bus:subscribe(self(), Filter).

%% Subscribe to a specific room/topic
cryptic_event_bus:subscribe_topic(self(), <<"room_general">>).

%% Publish an event to all subscribers
cryptic_event_bus:publish(#{
    type => deliver_message,
    from => <<"alice">>,
    message => <<"Hello!">>,
    timestamp => erlang:timestamp()
}).

%% Unsubscribe
cryptic_event_bus:unsubscribe(self()).

%% List all subscribers (debugging)
cryptic_event_bus:list_subscribers().
```

### Event Format

All events are **Erlang maps** with a `type` field that identifies the event category:

```erlang
#{
    type => EventType :: atom(),
    % ... additional fields specific to event type
}
```

### Subscriber Message Format

When an event is published, subscribers receive it as:
```erlang
{event, EventMap}
```

Example:
```erlang
receive
    {event, #{type := deliver_message, from := From, message := Msg}} ->
        display_message(From, Msg)
end.
```

---

## Message Flow & Components

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Interface Layer                         │
│  (cryptic_console, cryptic_ws_ui, or YOUR RUST TUI)                 │
│                                                                       │
│  - Subscribes to cryptic_event_bus for:                             │
│    * deliver_message (decrypted messages)                           │
│    * system_message (status updates)                                │
│    * websocket_message (server responses)                           │
│  - Publishes to event_bus:                                          │
│    * websocket_outbound (commands to server)                        │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
                            │ Events via cryptic_event_bus
                            │
┌───────────────────────────┴─────────────────────────────────────────┐
│                      Event Bus (gen_server)                          │
│                   cryptic_event_bus module                           │
│                                                                       │
│  - Routes events between components                                  │
│  - Filters events based on subscriber preferences                    │
│  - Monitors subscribers and cleans up dead processes                 │
└───────────────┬─────────────────────────────┬───────────────────────┘
                │                             │
    ┌───────────┘                             └───────────┐
    │                                                     │
    ▼                                                     ▼
┌─────────────────────────┐                  ┌─────────────────────────┐
│   Cryptic Engine        │                  │   WebSocket Client      │
│  (cryptic_engine)       │                  │  (cryptic_ws_client)    │
│                         │                  │                         │
│  - X3DH key agreement   │                  │  - mTLS authentication  │
│  - Double Ratchet       │                  │  - Connection mgmt      │
│  - Encryption/Decrypt   │                  │  - Message delivery     │
│  - Session management   │                  │  - Keepalive/reconnect  │
│                         │                  │                         │
│  Subscribes to:         │                  │  Subscribes to:         │
│  - websocket_message    │                  │  - websocket_outbound   │
│  Publishes:             │                  │  Publishes:             │
│  - deliver_message      │                  │  - websocket_message    │
│  - system_message       │                  │                         │
└─────────────────────────┘                  └─────────────────────────┘
            │                                            │
            │                                            │
            ▼                                            ▼
┌─────────────────────────┐                  ┌─────────────────────────┐
│  Storage (Callbacks)    │                  │   WebSocket Server      │
│  (cryptic_console_      │                  │  (cryptic_ws_handler)   │
│   callbacks)            │                  │                         │
│                         │                  │  - Certificate auth     │
│  - Load/save keys       │                  │  - Message routing      │
│  - Load/save sessions   │                  │  - Key bundle mgmt      │
│  - Encrypt DB storage   │                  │  - Pending messages     │
└─────────────────────────┘                  └─────────────────────────┘
```

### Component Responsibilities

#### 1. **UI Layer** (Your Rust TUI would go here)
- **Subscribe** to event bus for messages to display
- **Publish** user commands to event bus
- Handle keyboard input, screen rendering
- No direct crypto operations (all via engine callbacks)

#### 2. **Event Bus** (`cryptic_event_bus`)
- Central message broker
- No business logic - pure routing
- Started by supervisor, single instance

#### 3. **Cryptic Engine** (`cryptic_engine`)
- Implements all cryptographic operations
- Stateful `gen_server` managing sessions
- Uses callback behavior for storage/network/UI
- Subscribes to `websocket_message` events
- Publishes `deliver_message` and `system_message` events

#### 4. **WebSocket Client** (`cryptic_ws_client`)
- Maintains persistent connection to server
- Handles mTLS certificate authentication
- Automatic reconnection and message retry
- Subscribes to `websocket_outbound` events
- Publishes `websocket_message` events

#### 5. **Storage Callbacks** (`cryptic_console_callbacks`)
- Implements `cryptic_engine` behavior
- Loads/saves identity keys and session states
- Encrypts data at rest with user passphrase
- File-based storage in `~/.cryptic/`

---

## Event Types & Payloads

### Events Published TO the Event Bus

#### 1. `websocket_outbound` - Commands to Server
Published by UI when user wants to send something to server.

```erlang
#{
    type => websocket_outbound,
    message => #{
        <<"type">> => <<"send_message">>,  % or other command
        % ... additional fields depend on command type
    }
}
```

**Common Commands**:
- `<<"list_users">>` - Request list of registered users
- `<<"send_message">>` - Send encrypted message
- `<<"get_key_bundle">>` - Fetch user's public keys for X3DH
- `<<"upload_identity_keys">>` - Upload your public keys

#### 2. `deliver_message` - Decrypted Message for User
Published by `cryptic_engine` after successfully decrypting.

```erlang
#{
    type => deliver_message,
    from => <<"alice">> :: binary(),
    message => <<"Hello Bob!">> :: binary(),
    timestamp => erlang:timestamp()
}
```

#### 3. `system_message` - Status/Info Messages
Published by `cryptic_engine` for system notifications.

```erlang
#{
    type => system_message,
    message => <<"Connected to server">> :: binary()
}
```

#### 4. `websocket_message` - Server Responses
Published by `cryptic_ws_client` when server sends data.

```erlang
#{
    type => websocket_message,
    message => #{
        <<"type">> => <<"users">>,
        <<"users">> => [<<"alice">>, <<"bob">>, <<"charlie">>]
    }
}
```

**Common Server Message Types**:
- `<<"welcome">>` - Connection established
- `<<"users">>` - List of registered users
- `<<"key_bundle">>` - User's public keys (response to get_key_bundle)
- `<<"message">>` - Encrypted message from another user (X3DH or ratchet)
- `<<"message_sent">>` - Acknowledgment that message was delivered
- `<<"error">>` - Error occurred
- `<<"user_status">>` - User online/offline notification
- `<<"pending_messages_delivered">>` - Count of queued messages delivered

### Events Subscribed BY Components

#### UI Process Typical Filter
```erlang
Filter = fun(Event) ->
    case Event of
        #{type := deliver_message} -> true;      % Show to user
        #{type := system_message} -> true;       % Show status
        #{type := websocket_message} -> true;    % Server responses
        _ -> false
    end
end,
cryptic_event_bus:subscribe(self(), Filter).
```

#### Engine Process Filter
```erlang
Filter = fun(Event) ->
    case Event of
        #{type := websocket_message, 
          message := #{<<"type">> := MsgType}} when 
            MsgType =:= <<"message">>;     % Encrypted message to decrypt
            MsgType =:= <<"key_bundle">>   % Keys for X3DH
            -> true;
        _ -> false
    end
end.
```

#### WebSocket Client Filter
```erlang
Filter = fun(Event) ->
    case Event of
        #{type := websocket_outbound} -> true;  % Commands to send
        _ -> false
    end
end.
```

---

## WebSocket Protocol

### Server-Client Message Format

All WebSocket messages are **JSON-encoded** with a `type` field.

### Client → Server Messages

#### Upload Identity Keys (Initial Setup)
```json
{
  "type": "upload_identity_keys",
  "username": "alice",
  "identity_sign_public": "base64...",
  "identity_dh_public": "base64...",
  "signed_prekey_public": "base64...",
  "signed_prekey_signature": "base64...",
  "signed_prekey_id": 1
}
```

#### Upload One-Time Prekeys
```json
{
  "type": "upload_prekey_bundle",
  "username": "alice",
  "one_time_prekeys": [
    {"key_id": 1, "public_key": "base64..."},
    {"key_id": 2, "public_key": "base64..."}
  ]
}
```

#### Request Key Bundle (For X3DH)
```json
{
  "type": "get_key_bundle",
  "username": "bob"
}
```

#### Send X3DH Initial Message
```json
{
  "type": "x3dh",
  "message_id": "uuid-1234",
  "from_user": "alice",
  "to_user": "bob",
  "identity_key": "base64...",
  "ephemeral_key": "base64...",
  "used_one_time_prekey_id": 1,
  "ciphertext": "base64..."
}
```

#### Send Ratchet Message
```json
{
  "type": "ratchet",
  "message_id": "uuid-5678",
  "from_user": "alice",
  "to_user": "bob",
  "dh_public": "base64...",
  "previous_chain_length": 5,
  "message_number": 3,
  "ciphertext": "base64..."
}
```

#### List Users
```json
{
  "type": "list_users"
}
```

### Server → Client Messages

#### Welcome
```json
{
  "type": "welcome",
  "message": "Connected to Cryptic Server"
}
```

#### Success Response
```json
{
  "type": "success",
  "operation": "upload_identity_keys",
  "message": "Identity keys uploaded successfully"
}
```

#### Key Bundle Response
```json
{
  "type": "key_bundle",
  "username": "bob",
  "identity_sign_key": "base64...",
  "identity_dh_key": "base64...",
  "signed_prekey": {
    "key_id": 1,
    "public_key": "base64...",
    "signature": "base64..."
  },
  "one_time_prekey": {
    "key_id": 5,
    "public_key": "base64..."
  }
}
```

#### Users List
```json
{
  "type": "users",
  "users": ["alice", "bob", "charlie"]
}
```

#### Incoming Message (X3DH or Ratchet)
```json
{
  "type": "message",
  "message_type": "x3dh",  // or "ratchet"
  "from_user": "alice",
  "to_user": "bob",
  // ... message-specific fields
}
```

#### Message Sent Acknowledgment
```json
{
  "type": "message_sent",
  "message_id": "uuid-1234",
  "to_user": "bob",
  "timestamp": 1699999999
}
```

#### Error
```json
{
  "type": "error",
  "message": "User not found",
  "success": false
}
```

---

## Cryptographic Engine

### Core Module: `cryptic_engine`

**Location**: `src/cryptic_engine.erl`

The engine is a **stateful gen_server** that manages:
1. Identity keys (signing and DH keys)
2. Session states (one per peer)
3. X3DH key agreement
4. Double Ratchet encryption/decryption

### Callback Behavior: `cryptic_engine`

To integrate with the engine, you implement these callbacks:

#### Storage Callbacks
```erlang
-callback load_identity_keys(Username, Context) -> 
    {ok, IdentityKeys, UpdatedContext} | {error, Reason, Context}.

-callback save_identity_keys(Username, IdentityKeys, Context) ->
    {ok, UpdatedContext} | {error, Reason, Context}.

-callback load_session_state(Username, PeerUsername, Context) ->
    {ok, SessionState, UpdatedContext} | {error, not_found | term(), Context}.

-callback save_session_state(Username, PeerUsername, SessionState, Context) ->
    {ok, UpdatedContext} | {error, Reason, Context}.
```

**Identity Keys Format**:
```erlang
#{
    identity_sign_key => {PublicKey, PrivateKey},
    identity_dh_key => {PublicKey, PrivateKey},
    signed_prekey => {KeyId, PublicKey, PrivateKey},
    signed_prekey_signature => Signature,
    one_time_prekeys => #{KeyId => {PublicKey, PrivateKey}}
}
```

**Session State Format**: Opaque map from Double Ratchet module.

#### Network Callbacks
```erlang
-callback send_message_to_server(Username, Message, Context) ->
    {ok, UpdatedContext} | {error, Reason, Context}.
```

This is where you **publish to event bus**:
```erlang
send_message_to_server(_Username, Message, Context) ->
    cryptic_event_bus:publish(#{
        type => websocket_outbound,
        message => Message
    }),
    {ok, Context}.
```

#### UI Callbacks
```erlang
-callback deliver_message(FromUsername, Message, Timestamp, Context) ->
    {ok, UpdatedContext} | {error, Reason, Context}.

-callback system_message(Message, Context) ->
    {ok, UpdatedContext} | {error, Reason, Context}.
```

These publish events for UI to display:
```erlang
deliver_message(FromUsername, Message, Timestamp, Context) ->
    cryptic_event_bus:publish(#{
        type => deliver_message,
        from => FromUsername,
        message => Message,
        timestamp => Timestamp
    }),
    {ok, Context}.

system_message(Message, Context) ->
    cryptic_event_bus:publish(#{
        type => system_message,
        message => Message
    }),
    {ok, Context}.
```

### Engine State

The engine maintains:
```erlang
-record(cryptic_engine_state, {
    username :: binary(),
    identity_keys :: map(),
    sessions :: #{PeerUsername => SessionState},
    key_bundles :: #{PeerUsername => KeyBundle},
    ws_client_pid :: pid(),
    context :: map()  % Passed to callbacks
}).
```

---

## Storage Systems

### 1. Identity Keys Storage (`cryptic_lib`)

**Location**: `src/cryptic_lib.erl`

Keys stored in: `~/.cryptic/<username>/<server>_<port>/`

```
~/.cryptic/
└── alice/
    └── localhost_8443/
        ├── keys.encrypted       # Identity keys (encrypted with passphrase)
        ├── certificates/
        │   ├── alice.crt
        │   ├── alice.key
        │   └── ca.crt
        └── sessions/
            ├── bob.session      # Encrypted ratchet state
            └── charlie.session
```

**Encryption**: ChaCha20-Poly1305 with passphrase-derived keys

### 2. Message History (`cryptic_chat_storage`)

**Location**: `src/cryptic_chat_storage.erl`

SQLite database in `~/.cryptic/<username>/<server>_<port>/cryptic_chat.db`

**Schema**:
```sql
CREATE TABLE encrypted_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_user TEXT NOT NULL,
    to_user TEXT NOT NULL,
    server_host TEXT NOT NULL,
    server_port INTEGER NOT NULL,
    encrypted_message BLOB NOT NULL,
    salt BLOB NOT NULL,
    nonce BLOB NOT NULL,
    timestamp INTEGER NOT NULL,
    message_type TEXT DEFAULT 'text',
    read_status INTEGER DEFAULT 0,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);
```

**API**:
```erlang
%% Initialize storage
cryptic_chat_storage:init_storage(DbPath, Passphrase).

%% Save message
cryptic_chat_storage:save_encrypted_message(
    FromUser, ToUser, PlaintextMessage, 
    ServerHost, ServerPort, Timestamp, Passphrase
).

%% Query messages
cryptic_chat_storage:get_last_n_messages(N, Username, Passphrase).
cryptic_chat_storage:get_conversation(User1, User2, ServerInfo, Passphrase).
cryptic_chat_storage:get_messages_from_yesterday(Username, ServerInfo, Passphrase).
```

---

## Flutter Mobile App Architecture

The Flutter mobile app (`cryptic_app/`) is a full client implementation that
mirrors the Erlang client's cryptographic protocols while using Flutter's
reactive UI patterns and Riverpod for state management.

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Presentation Layer (Flutter)                  │
│  Screens: Splash, Login, Enrollment, Users, Chat                │
│  State: Riverpod providers (AuthNotifier, EnrollmentNotifier,   │
│         ConversationsNotifier, EngineProvider)                   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────────┐
│                     Services / Engine Layer                      │
│  CrypticEngine  — orchestrates crypto + network + sessions      │
│  AuthenticationService — cert loading, passphrase verification,  │
│                          engine construction                     │
│  EnrollmentService — QR → decrypt → CSR → cert → store          │
│  PassphraseEncryptionService — Argon2id + AES-256-CBC           │
└──────────┬─────────────────────┬────────────────────────────────┘
           │                     │
┌──────────┴──────────┐ ┌───────┴──────────────────────────────┐
│    Crypto Layer     │ │         Network Layer                │
│  X3DH (x3dh_engine) │ │  WebSocketClient (mTLS)              │
│  Double Ratchet     │ │  ConnectionManager (reconnect)       │
│  Ed25519, X25519    │ │  MessageQueue (offline outbound)     │
│  Blake2b KDF        │ │  ProtocolCodec (JSON ↔ messages)     │
│  ChaCha20-Poly1305  │ │                                      │
└──────────┬──────────┘ └───────┬──────────────────────────────┘
           │                     │
┌──────────┴─────────────────────┴────────────────────────────────┐
│                       Storage Layer                             │
│  SecureStorageService — flutter_secure_storage wrapper           │
│  EncryptedSecureStorage — passphrase-encrypted overlay           │
│  KeyStorageService — identity keys, prekeys, sessions (JSON)    │
│  CertificateStorageService — mTLS certs/key (PEM)               │
│  KeyRepository / SessionRepository — clean facades              │
│  EncryptedPreferences — app settings                            │
└─────────────────────────────────────────────────────────────────┘
```

### Project Structure

```
cryptic_app/lib/
├── main.dart                                 # Entry point (Riverpod root)
├── core/
│   ├── config/app_config.dart                # Dev/staging/prod config
│   ├── constants/crypto_constants.dart       # Key sizes, HKDF info strings
│   ├── errors/app_exceptions.dart            # CrypticException hierarchy
│   ├── theme/                                # Material 3 theming
│   └── utils/logger.dart                     # Redacting logger
│
├── data/
│   ├── crypto/
│   │   ├── keys/                             # IdentityKeyPair, KeyBundle,
│   │   │                                     # SignedPrekey, OneTimePrekey
│   │   ├── primitives/                       # Ed25519, X25519, HKDF,
│   │   │                                     # Blake2b KDF, ChaCha20-Poly1305
│   │   ├── ratchet/                          # DoubleRatchet, RatchetState
│   │   └── x3dh/x3dh_engine.dart            # X3DH sender/receiver
│   │
│   ├── engine/
│   │   ├── cryptic_engine.dart               # Main orchestrator
│   │   ├── engine_state.dart                 # EngineState, events, enums
│   │   ├── message_processor.dart            # Decode + decrypt incoming
│   │   └── session_manager.dart              # Per-peer ratchet sessions
│   │
│   ├── enrollment/
│   │   ├── enrollment_payload.dart           # QR envelope + payload parsing
│   │   ├── enrollment_crypto.dart            # Argon2id, HMAC, AES-CBC, Ed25519
│   │   ├── csr_generator.dart                # ECDSA P-256 keypair + PKCS#10 CSR
│   │   └── enrollment_service.dart           # 7-stage enrollment orchestrator
│   │
│   ├── network/
│   │   ├── protocol/                         # ProtocolCodec, client/server msgs
│   │   └── websocket/                        # WebSocketClient, MtlsConfig,
│   │                                         # ConnectionManager, MessageQueue
│   │
│   ├── services/
│   │   ├── authentication_service.dart       # Cert loading → engine setup
│   │   └── passphrase_encryption_service.dart # Argon2id + AES-256-CBC
│   │
│   └── storage/
│       ├── secure_storage/
│       │   ├── secure_storage_service.dart         # flutter_secure_storage
│       │   ├── encrypted_secure_storage.dart       # Passphrase-encrypted overlay
│       │   ├── key_storage_service.dart            # Keys + sessions (JSON)
│       │   └── certificate_storage_service.dart    # mTLS certs (PEM)
│       ├── repositories/
│       │   ├── key_repository.dart                 # Key CRUD facade
│       │   └── session_repository.dart             # Session CRUD facade
│       └── preferences/
│           └── encrypted_preferences.dart          # App settings
│
├── domain/
│   ├── models/                               # Contact, Conversation, Message
│   └── usecases/                             # Connect, Send, GetUsers, etc.
│
└── presentation/
    ├── app.dart                              # Root widget (screen routing)
    ├── providers/
    │   ├── auth_provider.dart                # AuthNotifier (login state)
    │   ├── enrollment_provider.dart          # EnrollmentNotifier (QR flow)
    │   ├── engine_provider.dart              # Engine Riverpod providers
    │   └── messages_provider.dart            # ConversationsNotifier
    ├── screens/
    │   ├── splash_screen.dart                # Startup + auth check
    │   ├── login_screen.dart                 # Username/passphrase/server
    │   ├── users_screen.dart                 # Online users (home)
    │   ├── chat_screen.dart                  # Chat conversation
    │   └── enrollment/
    │       ├── enrollment_flow_screen.dart    # Flow orchestrator
    │       ├── qr_scanner_screen.dart         # QR scanning / clipboard paste
    │       ├── passphrase_screen.dart          # Admin passphrase entry
    │       ├── enrollment_progress_screen.dart # Step progress + result
    │       └── set_passphrase_screen.dart      # User's own passphrase
    └── widgets/                              # Reusable UI components
```

### Enrollment Flow

Mobile enrollment uses QR codes instead of GPG keys. The admin creates an
encrypted enrollment package; the mobile app decrypts it and obtains an
mTLS client certificate.

```
Admin (cryptic-onboard)              Mobile App              Cryptic Server
─────────────────────               ──────────              ──────────────
1. create-mobile-enrollment
   → generates Ed25519 keypair
   → encrypts with Argon2id+AES
   → produces QR code
   → registers enrollment on server
                                    2. Scan QR code
                                    3. Enter admin passphrase
                                    4. Argon2id derive key
                                       → decrypt envelope
                                       → extract Ed25519 key,
                                         server URL, CA cert
                                    5. Generate ECDSA P-256 keypair
                                       → build PKCS#10 CSR
                                       → sign CSR with Ed25519 key
                                    6. Submit CSR ─────────────────→ Verify Ed25519
                                                                     signature
                                                                     Issue X.509 cert
                                       ←───────── signed cert ──────
                                    7. Store cert + key + CA
                                       in flutter_secure_storage
                                    8. Set personal passphrase
                                       → encrypt all stored keys
                                    9. Login screen → connect
```

### Passphrase-Based Key Encryption

After enrollment, the user sets a **personal passphrase** (distinct from
the one-time admin enrollment passphrase). All sensitive stored data is
encrypted at rest:

| What is encrypted | Storage key |
|---|---|
| Identity key pair (Ed25519 + X25519) | `cryptic_identity_keys` |
| Signed prekey | `cryptic_signed_prekey` |
| One-time prekeys | `cryptic_one_time_prekeys` |
| Full key bundle | `cryptic_key_bundle` |
| Client TLS private key (PEM) | `cryptic_cert_client_key` |
| Session states (per peer) | `cryptic_session_<peer>` |

**Encryption scheme:**
- **Key derivation**: Argon2id — 64 MiB memory, 3 iterations, 4 parallelism, 32-byte output
- **Cipher**: AES-256-CBC with PKCS7 padding
- **Per-value randomness**: Fresh 16-byte salt + 16-byte IV for each encrypted value
- **Verification**: A verifier (encrypted magic string) is stored at `cryptic_passphrase_verifier` so the passphrase can be checked on login without exposing key material

**How it works at runtime:**

```
┌────────────────┐    passphrase    ┌──────────────────────┐
│  Login Screen  │ ───────────────→ │ AuthenticationService │
└────────────────┘                  └──────────┬───────────┘
                                               │
                                    1. Verify passphrase
                                       (decrypt verifier)
                                               │
                                    2. Create EncryptedSecureStorage
                                       (wraps SecureStorageService)
                                               │
                                    3. Inject into KeyStorageService
                                       + CertificateStorageService
                                               │
                                    4. All subsequent reads/writes
                                       transparently encrypt/decrypt
                                       sensitive keys
                                               │
                                    5. Build engine + connect
```

`EncryptedSecureStorage` extends `SecureStorageService` and overrides
`read()` / `write()`. It checks whether a storage key is "sensitive"
(matches a known prefix list) and if so, encrypts the value on write and
decrypts on read. Non-sensitive keys pass through unmodified. Legacy
plaintext values (from before passphrase setup) are detected by a
`FormatException` on JSON parse and returned as-is for backward
compatibility.

### State Management (Riverpod)

The app uses Riverpod `StateNotifier` providers for reactive state:

| Provider | Notifier | State | Purpose |
|---|---|---|---|
| `authProvider` | `AuthNotifier` | `AuthStatus` | Login/logout, holds `CrypticEngine` |
| `enrollmentProvider` | `EnrollmentNotifier` | `EnrollmentStatus` | QR scan → passphrase → processing → set passphrase → done |
| `engineProvider` | (derived) | `CrypticEngine?` | Exposes engine from auth |
| `messagesProvider` | `ConversationsNotifier` | `Map<String, List<ChatMessage>>` | Per-peer message lists |

**Enrollment phases** (in order):
`scanQr` → `enterPassphrase` → `processing` → `setPassphrase` → `completed` / `failed`

### Key Crypto Differences from Erlang Client

| Aspect | Erlang Client | Flutter Client |
|---|---|---|
| KDF for ratchet chain keys | libsodium HMAC-SHA-512/256 | Blake2b (via `cryptography` package) |
| Root key update | HKDF | XOR mixing |
| AEAD cipher | ChaCha20-Poly1305 (libsodium) | ChaCha20-Poly1305 (`pointycastle`) |
| Key storage encryption | ChaCha20-Poly1305 + passphrase | AES-256-CBC + Argon2id passphrase |
| Secure storage backend | File-based (`~/.cryptic/`) | Platform keychain (iOS Keychain / Android Keystore) |
| mTLS key type | RSA or ECDSA | ECDSA P-256 (via enrollment CSR) |

### Dependencies

Key packages (see `pubspec.yaml` for versions):

| Package | Purpose |
|---|---|
| `flutter_riverpod` | State management |
| `pointycastle` | AES-CBC, PKCS7, SHA-256, HMAC, ECDSA |
| `cryptography` | Argon2id, Ed25519, X25519, ChaCha20-Poly1305, Blake2b |
| `flutter_secure_storage` | iOS Keychain / Android Keystore |
| `sqflite_sqlcipher` | Encrypted SQLite (message history — pending) |
| `web_socket_channel` | WebSocket transport |
| `mobile_scanner` | Camera QR scanning |
| `http` | HTTP client (enrollment CSR submission) |

### Common Modification Points

When working on the mobile app, here are the files most likely to need changes:

| Task | Primary files |
|---|---|
| Add a new screen | `presentation/screens/`, `presentation/app.dart` |
| Change enrollment flow | `enrollment_provider.dart`, `enrollment_flow_screen.dart`, `enrollment_service.dart` |
| Change login/auth | `auth_provider.dart`, `authentication_service.dart`, `login_screen.dart` |
| Change what gets encrypted | `encrypted_secure_storage.dart` (sensitive key list) |
| Change crypto parameters | `passphrase_encryption_service.dart`, `enrollment_crypto.dart` |
| Add protocol messages | `client_messages.dart`, `server_messages.dart`, `protocol_codec.dart` |
| Change key storage format | `key_storage_service.dart`, `identity_key_pair.dart` |
| Change WebSocket behavior | `websocket_client.dart`, `connection_manager.dart` |

---

## Building a New UI Client

### Step-by-Step Guide for Rust/Ratatui TUI

#### 1. **Start Event Bus and Engine**

From Erlang side (or via Erlport if calling from Rust):
```erlang
%% Start event bus
{ok, BusPid} = cryptic_event_bus:start_link().

%% Start engine with your callbacks
Config = #{
    username => <<"alice">>,
    server_host => <<"localhost">>,
    server_port => 8443,
    passphrase => <<"mypassphrase">>,
    callback_module => your_rust_callbacks_module
}.
{ok, EnginePid} = cryptic_engine:start_link(Config).

%% Start WebSocket client
{ok, WsPid} = cryptic_ws_client:start_link(
    <<"alice">>, <<"localhost">>, Config
).
```

#### 2. **Subscribe to Events**

Your Rust process (via Erlport or NIF) subscribes:
```erlang
%% Subscribe to messages for UI display
Filter = fun(Event) ->
    case Event of
        #{type := deliver_message} -> true;
        #{type := system_message} -> true;
        #{type := websocket_message} -> true;
        _ -> false
    end
end,
cryptic_event_bus:subscribe(YourRustPid, Filter).
```

#### 3. **Receive Events in Your Event Loop**

Your Rust TUI main loop:
```rust
loop {
    select! {
        // Handle Erlang events
        event = erlport_receiver.recv() => {
            match event {
                Event::DeliverMessage { from, message, timestamp } => {
                    // Add to chat window
                    chat_view.add_message(from, message, timestamp);
                    terminal.draw()?;
                }
                Event::SystemMessage { message } => {
                    // Show in status bar
                    status_bar.set_message(message);
                    terminal.draw()?;
                }
                Event::WebSocketMessage { message } => {
                    // Handle server responses (users list, etc.)
                    handle_server_message(message);
                }
            }
        }
        
        // Handle keyboard input
        key = keyboard.read() => {
            match key {
                Key::Enter => {
                    let msg = input_buffer.take();
                    send_message_to_current_peer(msg);
                }
                // ... other keys
            }
        }
    }
}
```

#### 4. **Send User Commands**

When user types a message:
```rust
fn send_message_to_peer(to_user: &str, message: &str) {
    let event = map! {
        "type" => "websocket_outbound",
        "message" => map! {
            "type" => "send_message",
            "to_user" => to_user,
            "plaintext" => message
        }
    };
    
    // Publish to Erlang event bus
    erlport::publish_event(event)?;
}
```

The engine will:
1. Intercept this via subscription
2. Encrypt the message
3. Forward to WebSocket client
4. WebSocket client sends to server

#### 5. **Handle Server Responses**

Example: Display list of users
```rust
fn handle_websocket_message(msg: Map) {
    match msg.get("type") {
        Some("users") => {
            let users: Vec<String> = msg.get("users")?.as_array()?;
            user_list_view.set_users(users);
            terminal.draw()?;
        }
        Some("error") => {
            let error_msg = msg.get("message")?;
            show_error_popup(error_msg);
        }
        // ... other message types
    }
}
```

### Key Integration Points for Rust TUI

#### A. **Erlport or NIF?**

**Option 1: Erlport** (easier, less performance)
- Erlang VM runs as parent process
- Rust communicates via stdin/stdout
- Use `erlport` crate for encoding/decoding Erlang terms

**Option 2: Rustler NIF** (harder, better performance)
- Rust compiled as native library (.so)
- Called directly from Erlang
- Use `rustler` crate
- More complex but integrated

#### B. **Message Encoding**

Events are Erlang maps. In Rust (via Erlport):
```rust
use erlport::{Atom, Map, List};

// Erlang: #{type => deliver_message, from => <<"alice">>}
let event = Map::from([
    (Atom::from("type"), Atom::from("deliver_message")),
    (Atom::from("from"), Binary::from("alice")),
    // ...
]);
```

#### C. **Ratatui Layout Example**

```rust
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Terminal,
};

fn draw_ui(terminal: &mut Terminal, app: &App) {
    terminal.draw(|f| {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),      // Status bar
                Constraint::Min(10),        // Chat messages
                Constraint::Length(3),      // Input box
            ])
            .split(f.size());

        // Status bar
        let status = Paragraph::new(format!(
            "Connected: {} | Peer: {} | Messages: {}",
            app.connected, app.current_peer, app.message_count
        ))
        .block(Block::default().borders(Borders::ALL).title("Status"));
        f.render_widget(status, chunks[0]);

        // Chat messages
        let messages: Vec<ListItem> = app.messages
            .iter()
            .map(|m| ListItem::new(format!("[{}] {}: {}", 
                m.timestamp, m.from, m.text)))
            .collect();
        let message_list = List::new(messages)
            .block(Block::default().borders(Borders::ALL).title("Chat"));
        f.render_widget(message_list, chunks[1]);

        // Input box
        let input = Paragraph::new(app.input_buffer.as_str())
            .block(Block::default().borders(Borders::ALL).title("Input"));
        f.render_widget(input, chunks[2]);
    })?;
}
```

---

## Reference Implementation

### Existing Terminal UI: `cryptic_console`

**Location**: `src/cryptic_console.erl`

This is the reference Erlang implementation. Key sections to study:

#### Event Subscription
```erlang
%% src/cryptic_console.erl:218
ConsoleFilter = fun(Event) ->
    case Event of
        #{type := deliver_message} -> true;
        #{type := system_message} -> true;
        #{type := websocket_message} -> true;
        _ -> false
    end
end,
ok = cryptic_event_bus:subscribe(ConsolePid, ConsoleFilter).
```

#### Event Handling
```erlang
%% src/cryptic_console.erl:430-450
receive
    {event, #{type := system_message, message := Message}} ->
        display_system_message(Message),
        console_loop(State);
        
    {event, #{type := deliver_message, 
              from := FromUsername, 
              message := Message, 
              timestamp := Timestamp}} ->
        display_chat_message(FromUsername, Message, Timestamp),
        maybe_save_to_history(Message),
        console_loop(State);
        
    {event, #{type := websocket_message, message := Message}} ->
        handle_server_message(Message),
        console_loop(State)
end.
```

#### Publishing Outbound Messages
```erlang
%% src/cryptic_console_callbacks.erl:177-182
cryptic_event_bus:publish(#{
    type => websocket_outbound,
    message => #{
        <<"type">> => <<"send_message">>,
        <<"to_user">> => ToUser,
        <<"plaintext">> => Plaintext
    }
}).
```

### WebSocket Client Reference

**Location**: `src/cryptic_ws_client.erl`

#### Subscription to Outbound Events
```erlang
%% src/cryptic_ws_client.erl:302
WsOutboundFilter = fun(Event) ->
    case Event of
        #{type := websocket_outbound} -> true;
        _ -> false
    end
end,
ok = cryptic_event_bus:subscribe(self(), WsOutboundFilter).
```

#### Publishing Inbound Messages
```erlang
%% src/cryptic_ws_client.erl:857-864
cryptic_event_bus:publish(#{
    type => websocket_message,
    message => DecodedMessage
}).
```

---

## Quick Start Checklist for Rust TUI

- [ ] Set up Erlang VM and start event bus
- [ ] Choose integration method (Erlport or Rustler NIF)
- [ ] Implement event subscription in Rust
- [ ] Create Ratatui UI with message list, input box, status bar
- [ ] Handle keyboard input and publish `websocket_outbound` events
- [ ] Subscribe to `deliver_message`, `system_message`, `websocket_message`
- [ ] Display received messages in UI
- [ ] Handle server responses (users list, errors, etc.)
- [ ] Implement storage callbacks (or reuse existing Erlang modules)
- [ ] Test with existing Erlang server

---

## Event Bus State Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        Event Bus Lifecycle                        │
└──────────────────────────────────────────────────────────────────┘

                    Application Start
                           │
                           ▼
                  ┌─────────────────┐
                  │  Event Bus      │
                  │  gen_server     │
                  │  started        │
                  └────────┬────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
        ┌─────────┐  ┌──────────┐  ┌────────┐
        │   UI    │  │  Engine  │  │   WS   │
        │ Process │  │ Process  │  │ Client │
        └────┬────┘  └─────┬────┘  └───┬────┘
             │             │            │
             │ subscribe() │            │
             └─────────────┼────────────┘
                           │
                  ┌────────▼────────┐
                  │  Subscribers    │
                  │  Map stored     │
                  │  Pids monitored │
                  └────────┬────────┘
                           │
                    Normal Operation
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           │               │               │
    publish(Event1)  publish(Event2)  publish(Event3)
           │               │               │
           └───────────────┼───────────────┘
                           │
                  ┌────────▼────────┐
                  │  Event Bus      │
                  │  evaluates      │
                  │  filters        │
                  └────────┬────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
         UI receives   Engine       WS Client
         matching      receives     receives
         events        matching     matching
                       events       events
```

---

## Debugging Tips

### 1. **Monitor Event Bus**
```erlang
%% See all subscribers
cryptic_event_bus:list_subscribers().

%% Subscribe with debug filter
DebugFilter = fun(Event) -> 
    io:format("Event: ~p~n", [Event]),
    true
end,
cryptic_event_bus:subscribe(self(), DebugFilter).
```

### 2. **Trace Events**
```erlang
%% Enable debug logging
application:set_env(cryptic, debug, true).

%% Watch message flow
dbg:tracer(),
dbg:p(all, c),
dbg:tpl(cryptic_event_bus, publish, []).
```

### 3. **Check Connectivity**
```erlang
%% Is WebSocket connected?
gen_server:call(cryptic_ws_client, get_connection_status).

%% Check engine state
gen_server:call(cryptic_engine, get_state_info).
```

---

## Common Pitfalls

1. **Forgetting to Subscribe**: Events won't arrive if you don't subscribe!
2. **Wrong Filter**: Double-check your filter function matches event types
3. **Binary vs String**: Usernames are **binaries** (`<<"alice">>`), not strings
4. **Map Atom Keys**: Event maps use **atom keys** (`:type`), server JSON uses **binary keys** (`<<"type">>`)
5. **Blocking in Handlers**: Event handling should be fast; defer heavy work
6. **Not Monitoring Supervisor**: If event bus crashes, your subscriptions are lost

---

## Further Reading

- **Event Manager**: `src/cryptic_event_manager.erl` - Logging infrastructure
- **Double Ratchet**: `src/cryptic_double_ratchet.erl` - Crypto implementation
- **X3DH**: `src/cryptic_lib.erl` (X3DH functions) - Key agreement
- **Storage**: `src/cryptic_chat_storage.erl` - Encrypted SQLite DB
- **Protocol Docs**: Signal's X3DH and Double Ratchet specifications

---

## Questions for Your AI Assistant

When starting your Rust TUI project, ask your AI assistant:

1. "How do I set up Erlport to communicate with the Cryptic event bus?"
2. "Show me a Ratatui layout for a chat application with event-driven updates"
3. "How do I encode Erlang maps in Rust for the event bus?"
4. "What's the best way to handle async events in Ratatui's main loop?"
5. "How do I parse binary WebSocket messages from Erlang in Rust?"

---

**Document Version**: 1.1  
**Last Updated**: April 2026  
**Author**: Generated for Cryptic Project

This document should provide your AI assistant with everything needed to
understand and integrate with the Cryptic system — both the Erlang server
event bus architecture and the Flutter mobile app. 🚀
