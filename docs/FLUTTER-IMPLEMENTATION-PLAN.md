# Cryptic Flutter App Implementation Plan

> **Version**: 1.0  
> **Last Updated**: November 2025  
> **Related Documents**: [`FLUTTER-ARCHITECTURE.md`](./FLUTTER-ARCHITECTURE.md), [`AGENTS.md`](../AGENTS.md)

This plan outlines the execution approach for delivering a Flutter-based
Cryptic client that matches the architecture in `docs/FLUTTER-ARCHITECTURE.md`.
It breaks the work into sequenced milestones, describes responsibilities,
highlights dependencies, and defines validation checkpoints to ensure an
end-to-end encrypted chat experience aligned with the Erlang reference
implementation.

---

## 1. Guiding Principles

1. **Cryptographic Parity**: Preserve exact compatibility with the Erlang
   client—X3DH key agreement, Double Ratchet messaging, mTLS transport, and
   identical wire protocol.
2. **Layer Boundaries**: Respect architecture separation
   (UI → Business Logic → Crypto/Network → Storage) to enable testability and
   future platform ports.
3. **Security First**: Treat hardening, threat modeling, and testing as
   first-class deliverables throughout—not post-launch afterthoughts.
4. **Offline Tolerance**: Design for intermittent connectivity from day
   one—queue outbound messages, persist sessions, display sync status.
5. **Privacy by Default**: No analytics, no read receipts by default,
   minimal metadata exposure, dark theme for visual privacy.

---

## 2. Milestones & Timeline

| Milestone | Target Duration | Primary Outputs | Acceptance Criteria |
|-----------|-----------------|-----------------|---------------------|
| **M1: Project Bootstrap** | Week 1 | Flutter project scaffold, CI lint/test pipeline, environment configs | CI runs on PR; baseline Riverpod wiring; Android/iOS/web builds succeed |
| **M2: Crypto Primitives** | Weeks 2–4 | `data/crypto/*` primitives (Ed25519, X25519, ChaCha20-Poly1305, HKDF); X3DH and Double Ratchet engines; unit tests with Erlang vectors | All crypto unit tests green; encrypt/decrypt parity with Erlang fixtures |
| **M3: Network Layer** | Weeks 4–6 | mTLS WebSocket client, protocol encoder/decoder, connection manager with retry/heartbeat | Connects to staging server; welcome/error handling validated; offline queue functional |
| **M4: Storage Layer** | Weeks 6–7 | Secure key storage (`flutter_secure_storage`), SQLCipher message DB, DAOs, repository implementations | Keys persist across restarts; DB encrypted; CRUD unit tests passing |
| **M5: Engine Orchestration** | Weeks 7–9 | `CrypticEngine`, `SessionManager`, `MessageProcessor`, domain use-cases wired | Engine integration tests: X3DH handshake + ratchet round-trip; state survives restart |
| **M6: UI & UX** | Weeks 9–11 | All screens (splash, auth, chat, contacts, settings), Riverpod providers, theming | Chat flow usable on device; dark theme default; accessibility labels present |
| **M7: Enrollment & Certificate Management** | Weeks 11–13 | GPG enrollment flow, QR code scanner, admin tooling, automatic cert renewal | QR enrollment succeeds; certs auto-renew; admin tools documented |
| **M8: Integration & Hardening** | Weeks 14–15 | End-to-end integration tests, security review, in-app update mechanism | Two-device chat succeeds; penetration findings triaged; update check wired |
| **M9: Release & Distribution** | Week 16 | Signed builds (APK, IPA), distribution pipeline (self-host, F-Droid), docs | RC signed with checksums; installation docs published; smoke tests on physical devices |

---

## 3. Workstreams & Tasks

### 3.1 Project Bootstrap (M1)

| Task | Description | Outputs |
|------|-------------|---------|
| Scaffold project | `flutter create --org com.cryptic cryptic_app`, apply folder structure from architecture doc | `lib/core`, `lib/data`, `lib/domain`, `lib/presentation` |
| Add dependencies | Integrate `flutter_riverpod`, `pointycastle`, `cryptography`, `web_socket_channel`, `flutter_secure_storage`, `sqflite_sqlcipher`, `uuid`, `logger`, `intl`, `path_provider` | `pubspec.yaml` |
| Configure linting | Enable `flutter analyze`, strict lints in `analysis_options.yaml`, pre-commit hook | Zero lint warnings on CI |
| Setup CI pipeline | GitHub Actions workflow: lint, test, build APK/IPA artifacts on PR | `.github/workflows/ci.yml` |
| Environment config | Create `app_config.dart` with dev/staging/prod server URLs, certificate asset paths | `lib/core/config/app_config.dart` |
| Logging utility | Implement `logger.dart` with log levels, secret redaction | `lib/core/utils/logger.dart` |

### 3.2 Cryptography Port (M2)

| Task | Description | Outputs |
|------|-------------|---------|
| Primitives wrappers | Ed25519 sign/verify, X25519 DH, ChaCha20-Poly1305 AEAD, HKDF | `lib/data/crypto/primitives/*.dart` |
| Key management | Key generation, serialization (base64), validation helpers | `lib/data/crypto/keys/*.dart` |
| X3DH engine | Port `cryptic_lib.erl` X3DH initiator/responder; verify signature, 4-DH, HKDF derivation | `lib/data/crypto/x3dh/x3dh_engine.dart` |
| Double Ratchet | Port `cryptic_double_ratchet.erl`: session init, DH ratchet, chain advancement, skipped keys | `lib/data/crypto/ratchet/double_ratchet.dart` |
| Erlang test vectors | Export fixtures from Erlang repo; Dart tests assert byte-for-byte parity | `test/unit/crypto/x3dh_test.dart`, `double_ratchet_test.dart` |
| Edge-case tests | Out-of-order messages, rekey, one-time prekey exhaustion | Additional test cases |

### 3.3 Network Layer (M3)

| Task | Description | Outputs |
|------|-------------|---------|
| mTLS config | Load client cert/key, CA bundle; create `SecurityContext`; pin CA | `lib/data/network/websocket/mtls_config.dart` |
| WebSocket client | Port `cryptic_ws_client.erl`: connect, listen, send, handle disconnect | `lib/data/network/websocket/websocket_client.dart` |
| Connection manager | Reconnect with exponential backoff, heartbeats/keepalive, connection state stream | `lib/data/network/websocket/connection_manager.dart` |
| Offline queue | Queue outbound messages when disconnected; flush on reconnect | `lib/data/network/websocket/message_queue.dart` |
| Protocol codec | JSON encode/decode for `welcome`, `users`, `key_bundle`, `x3dh`, `ratchet`, `error` | `lib/data/network/protocol/*.dart` |
| Mock WS server | Test harness using `web_socket_channel` for integration tests | `test/mocks/mock_ws_server.dart` |

### 3.4 Storage Layer (M4)

| Task | Description | Outputs |
|------|-------------|---------|
| Secure key storage | Store identity keys via `flutter_secure_storage`; biometric gate option | `lib/data/storage/secure_storage/key_storage.dart` |
| Certificate storage | Persist mTLS certs; expose load helpers | `lib/data/storage/secure_storage/certificate_storage.dart` |
| Passphrase handling | Hash passphrase with Argon2; derive DB encryption key | `lib/data/storage/secure_storage/passphrase_storage.dart` |
| SQLCipher database | Initialize encrypted SQLite; schema migrations | `lib/data/storage/database/database.dart` |
| DAOs | CRUD for messages, sessions, contacts | `lib/data/storage/database/daos/*.dart` |
| Repository impls | Implement abstract repos from `domain/repositories` | `lib/data/storage/repositories_impl/*.dart` |
| Data purge API | "Delete All Data", per-conversation delete, session reset | Methods in storage repository |

### 3.5 Engine Orchestration (M5)

| Task | Description | Outputs |
|------|-------------|---------|
| CrypticEngine | Port `cryptic_engine.erl`: init, key upload, session bootstrap, send/receive | `lib/data/engine/cryptic_engine.dart` |
| Engine state | Immutable state class, status enum, copyWith | `lib/data/engine/engine_state.dart` |
| Session manager | Map peer → SessionState; load/save via storage repo | `lib/data/engine/session_manager.dart` |
| Message processor | Route incoming server messages to handlers; emit UI events | `lib/data/engine/message_processor.dart` |
| DI setup | Wire repos into engine via `injection.dart` | `lib/core/di/injection.dart` |
| Domain use-cases | `SendMessage`, `ReceiveMessage`, `InitializeSession`, `UploadKeys` | `lib/domain/usecases/*.dart` |
| Integration tests | Fake repos; simulate handshake, send/receive, restart recovery | `test/integration/engine_test.dart` |

### 3.6 UI Layer (M6)

| Task | Description | Outputs |
|------|-------------|---------|
| Riverpod providers | `engineProvider`, `messagesProvider`, `contactsProvider`, `connectionProvider` | `lib/presentation/providers/*.dart` |
| Splash screen | Load keys, show progress, route to unlock or setup | `lib/presentation/screens/splash/splash_screen.dart` |
| Auth screens | Setup (generate keys), Unlock (passphrase entry) | `lib/presentation/screens/auth/*.dart` |
| Chat screens | Chat list, individual chat with message bubbles, input field, typing indicator | `lib/presentation/screens/chat/*.dart` |
| Contacts screens | User list, contact detail with fingerprint, session stats | `lib/presentation/screens/contacts/*.dart` |
| Settings screen | Account, connection, security, privacy, appearance sections per architecture doc | `lib/presentation/screens/settings/*.dart` |
| Shared widgets | `ConnectionStatus`, `ErrorDialog`, `LoadingOverlay` | `lib/presentation/widgets/*.dart` |
| Theming | `AppColors`, `AppTextStyles`, dark/light/system support | `lib/core/theme/*.dart` |
| Accessibility | Semantic labels, large text support, color contrast | Verified with Flutter a11y tools |

### 3.7 Enrollment & Certificate Management (M7)

**Context**: The Cryptic server requires GPG-signed CSRs for issuing short-lived mTLS certificates with automatic renewal. This milestone implements a hybrid approach where admin-generated GPG keys are securely transferred to mobile devices via QR code enrollment.

#### 3.7.1 Admin Tooling

| Task | Description | Outputs |
|------|-------------|---------|
| Extend cryptic-onboard script | Add `create-enrollment` subcommand to existing `./cryptic/bin/cryptic-onboard` script | `cryptic/bin/cryptic-onboard` |
| GPG key generation for user | Reuse existing `generate_gpg_key()` function with batch mode for admin use | Modified function with optional parameters |
| Enrollment package creator | New function: `create_enrollment_package()` - Bundle GPG keys, username, server config into encrypted JSON; generate QR code | New function in cryptic-onboard |
| Encryption schema | Use ChaCha20-Poly1305 with 256-bit key derived from admin passphrase (Argon2id); include salt, nonce | Encrypted payload format spec |
| QR code format | JSON: `{"v":1, "salt":"base64", "nonce":"base64", "ciphertext":"base64"}`; max 2953 bytes (QR version 40-L) | QR payload schema doc |
| Batch enrollment | Add `batch-enroll` subcommand; read CSV input, generate multiple enrollment packages | New function in cryptic-onboard |
| Admin documentation | Guide: use cryptic-onboard commands, print/share QR codes securely | `docs/ADMIN-ENROLLMENT.md` |

**Encrypted Payload Schema** (before QR encoding):
```erlang
#{
    version => 1,
    username => <<"alice">>,
    server => #{
        host => <<"cryptic.example.com">>,
        port => 8443,
        ca_cert => <<"-----BEGIN CERTIFICATE-----\n...">>,
        enrollment_token => <<"admin-generated-uuid">>
    },
    gpg_keypair => #{
        public_key => <<"-----BEGIN PGP PUBLIC KEY BLOCK-----\n...">>,
        private_key => <<"-----BEGIN PGP PRIVATE KEY BLOCK-----\n...">>,
        key_id => <<"ABCD1234EFGH5678">>,
        passphrase => null  % Optional: encrypt private key itself
    },
    issued_at => 1736102400,
    expires_at => 1767638400  % 1 year validity
}
```

#### 3.7.2 Mobile Enrollment Flow

| Task | Description | Outputs |
|------|-------------|---------|
| QR code scanner UI | Camera permission, QR detection using `mobile_scanner` package, preview overlay | `lib/presentation/screens/enrollment/qr_scanner_screen.dart` |
| Passphrase prompt | Ask user for admin-provided decryption passphrase; show hint if available | `lib/presentation/screens/enrollment/passphrase_input_screen.dart` |
| Enrollment package parser | Decrypt QR payload, validate schema, extract GPG keys and server config | `lib/data/enrollment/enrollment_parser.dart` |
| GPG key import | Parse PGP armored keys, validate key integrity, store in secure storage | `lib/data/crypto/gpg/gpg_key_manager.dart` |
| Certificate request flow | Generate Ed25519 identity keys, create CSR, sign with GPG key, upload to server | `lib/data/enrollment/certificate_requester.dart` |
| Enrollment state machine | States: `scanning` → `decrypting` → `importing_keys` → `requesting_cert` → `complete` / `error` | `lib/domain/entities/enrollment_state.dart` |
| Error handling | Invalid QR, wrong passphrase, expired enrollment, server rejection | User-friendly error messages |

**Mobile UI Flow**:
1. **Welcome Screen**: "Scan Enrollment QR Code" button
2. **QR Scanner**: Camera preview with alignment guides
3. **Passphrase Input**: "Enter passphrase provided by administrator"
4. **Processing**: Loading indicator with status updates
5. **Success**: "Enrollment complete! You can now start chatting."
6. **Error**: Specific error message + retry button

#### 3.7.3 GPG Integration

| Task | Description | Outputs |
|------|-------------|---------|
| OpenPGP library | Integrate `openpgp` Dart package (or `pointycastle` PGP impl) | `pubspec.yaml` dependency |
| GPG key storage | Store GPG private key in `flutter_secure_storage`; separate from Ed25519 identity keys | `lib/data/storage/secure_storage/gpg_storage.dart` |
| CSR signing | Generate PKCS#10 CSR with Ed25519 public key; sign CSR bytes with GPG key | `lib/data/crypto/gpg/csr_signer.dart` |
| Signature verification | Server-side: verify GPG signature on CSR using stored public key | Erlang: `cryptic_gpg_verifier.erl` |
| Key rotation plan | Document process for rotating compromised GPG keys; re-enrollment flow | `docs/KEY-ROTATION.md` |

**CSR Signing Flow**:
```dart
// 1. Generate Ed25519 identity keys (for X3DH/messaging)
final identityKeys = await generateIdentityKeys();

// 2. Create CSR with identity public key
final csr = createCSR(
  publicKey: identityKeys.publicKey,
  username: username,
  commonName: 'cryptic-user-$username',
);

// 3. Sign CSR with GPG private key
final gpgKey = await loadGPGKey();
final signature = gpgKey.sign(csr.toDer());

// 4. Upload to server
final cert = await uploadSignedCSR(
  username: username,
  csr: csr.toDer(),
  signature: signature,
  gpgKeyId: gpgKey.keyId,
);
```

#### 3.7.4 Server-Side Enrollment Endpoint

| Task | Description | Outputs |
|------|-------------|---------|
| Enrollment API | New endpoint: `POST /api/enroll` accepting signed CSR, username, token | `apps/cryptic_server/src/cryptic_enroll_handler.erl` |
| Token validation | Verify enrollment token matches admin-generated value; one-time use | Token storage in Mnesia |
| GPG signature verification | Extract GPG key ID from signature, lookup public key, verify signature on CSR | Use `gpgme` Erlang NIF or `:public_key` module |
| Certificate issuance | Generate short-lived X.509 cert (7 days validity) signed by server CA | Existing cert generation code |
| User provisioning | Create user account, store GPG public key, initialize key bundle storage | Database schema update |
| Rate limiting | Prevent brute-force enrollment attempts; lockout after 5 failed attempts | Token attempt counter |

**Endpoint Specification**:
```erlang
% POST /api/enroll
% Body: #{
%   username => <<"alice">>,
%   enrollment_token => <<"uuid">>,
%   csr => <<"-----BEGIN CERTIFICATE REQUEST-----...">>,
%   gpg_signature => <<"-----BEGIN PGP SIGNATURE-----...">>,
%   gpg_key_id => <<"ABCD1234">>
% }
% Response: #{
%   certificate => <<"-----BEGIN CERTIFICATE-----...">>,
%   expires_at => 1736188800,
%   ca_cert => <<"-----BEGIN CERTIFICATE-----...">>
% }
```

#### 3.7.5 Automatic Certificate Renewal

| Task | Description | Outputs |
|------|-------------|---------|
| Renewal scheduler | Background task checks cert expiry; renew when <2 days remaining | `lib/data/certificate/renewal_scheduler.dart` |
| CSR regeneration | Create new CSR with same Ed25519 keys, sign with GPG key | Reuse CSR signing code |
| Renewal endpoint | Server: `POST /api/renew` validates existing cert + signed CSR | `cryptic_renew_handler.erl` |
| Retry logic | Exponential backoff on failure; alert user if renewal fails repeatedly | UI notification + retry button |
| Offline handling | Queue renewal request; retry when connectivity restored | Store pending renewal flag |
| Testing | Mock time progression; verify renewal triggered at correct threshold | `test/integration/cert_renewal_test.dart` |

**Renewal Flow**:
```dart
class CertificateRenewalScheduler {
  Timer? _timer;
  
  void start() {
    _timer = Timer.periodic(Duration(hours: 6), (_) async {
      final cert = await loadCurrentCertificate();
      final daysUntilExpiry = cert.expiresAt.difference(DateTime.now()).inDays;
      
      if (daysUntilExpiry <= 2) {
        await renewCertificate();
      }
    });
  }
  
  Future<void> renewCertificate() async {
    try {
      final csr = await generateCSR(); // Same Ed25519 keys
      final signature = await signCSRWithGPG(csr);
      final newCert = await apiClient.renewCertificate(csr, signature);
      await saveCertificate(newCert);
      logger.info('Certificate renewed successfully');
    } catch (e) {
      logger.error('Certificate renewal failed: $e');
      scheduleRetry();
    }
  }
}
```

#### 3.7.6 Security Considerations

| Task | Description | Outputs |
|------|-------------|---------|
| QR code security | Encrypt payload; never encode raw private keys; short-lived enrollment tokens | Security audit doc |
| Passphrase strength | Require ≥16 characters for enrollment decryption; use Argon2id with high cost | Configurable parameters |
| Key storage audit | Verify GPG keys only accessible via secure storage; never logged or cached | Penetration test |
| Man-in-the-middle | Validate server CA cert during enrollment; pin CA fingerprint in QR payload | Certificate pinning |
| Revocation mechanism | Admin tool to revoke compromised GPG keys; server rejects revoked keys | `tools/admin/revoke_key.erl` |
| Enrollment expiry | QR codes valid for 48 hours; tokens expire after first use or timeout | Server-side expiry checks |

#### 3.7.7 Testing Strategy

| Test Type | Scope | Examples |
|-----------|-------|----------|
| Unit | Individual components | QR parser, GPG signer, CSR generator |
| Integration | End-to-end enrollment | QR scan → import → cert issuance → login |
| Security | Threat scenarios | Expired QR, tampered payload, revoked key, wrong passphrase |
| Performance | Large-scale operations | 1000 enrollment packages, concurrent renewals |
| Recovery | Error handling | Network failure during enrollment, interrupted renewal |

**Test Cases**:
- [ ] Valid QR code enrollment completes successfully
- [ ] Invalid passphrase rejected with clear error
- [ ] Expired enrollment token rejected by server
- [ ] Tampered QR payload fails decryption
- [ ] Certificate renewal succeeds 2 days before expiry
- [ ] Renewal retries after network failure
- [ ] Revoked GPG key rejected by server
- [ ] QR code with invalid schema version rejected

### 3.8 Quality & Security (M8)

| Task | Description | Outputs |
|------|-------------|---------|
| Widget tests | Chat screen, contacts screen, settings toggles | `test/widget/*.dart` |
| Integration tests | Full message flow on instrumented device | `test/integration/message_flow_test.dart` |
| Coverage gate | Require >80% line coverage on `data/crypto`, `data/engine` | CI enforced threshold |
| Static analysis | Zero warnings from `flutter analyze` | CI gate |
| Security review | Threat model doc; key storage audit; cert pinning validation; memory clearing | `docs/SECURITY-REVIEW.md` |
| Dependency audit | Run `flutter pub outdated`, check for CVEs | Documented in release notes |
| Update mechanism | Version endpoint fetch, checksum validation, optional force-update | `lib/core/update/update_checker.dart` |

### 3.9 Release Engineering (M9)

| Task | Description | Outputs |
|------|-------------|---------|
| Signing assets | Android keystore, iOS certs; store in secure vault | `android/key.properties`, Xcode config |
| Release scripts | Build, sign, generate checksums, GPG-sign, upload to self-host | `scripts/release.sh` |
| F-Droid metadata | `metadata/com.cryptic.messenger.yml`, reproducible build config | `fdroid-repo/` |
| IPFS publish (optional) | Add release APK to IPFS; record CID | Documented CID |
| Installation docs | User-facing guide: enable unknown sources, verify checksum, install | `docs/INSTALL.md` |
| Physical device tests | Smoke test on Android + iOS hardware | QA sign-off checklist |

---

## 4. Dependencies & Infrastructure

### 4.1 External Dependencies

| Dependency | Purpose | Notes |
|------------|---------|-------|
| `pointycastle: ^3.9.0` | Ed25519, X25519, ChaCha20-Poly1305, RSA | Core crypto |
| `cryptography: ^2.7.0` | HKDF, Argon2id, additional primitives | Supplement pointycastle |
| `openpgp: ^2.0.0` | GPG key parsing, signing, verification | For CSR signing |
| `mobile_scanner: ^3.5.0` | QR code scanning | Camera access, ML Kit |
| `web_socket_channel: ^2.4.0` | WebSocket client | mTLS via `SecureSocket` |
| `flutter_secure_storage: ^9.0.0` | Hardware-backed key storage | iOS Keychain / Android Keystore |
| `sqflite_sqlcipher: ^3.0.0` | Encrypted SQLite | Passphrase-derived key |
| `flutter_riverpod: ^2.4.0` | State management | Preferred over Provider |
| `uuid: ^4.2.0` | Message IDs, enrollment tokens | UUIDv4 |
| `path_provider: ^2.1.0` | File paths | For DB location |
| `logger: ^2.0.0` | Logging | Structured, redacted |
| `intl: ^0.18.0` | Date formatting | i18n ready |
| `qr_flutter: ^4.1.0` | QR code generation | Admin tooling |

### 4.2 Infrastructure Requirements
enrollment API, test users, seeded messages | Backend team |
| Enrollment endpoint | `/api/enroll`, `/api/renew` with GPG signature verification | Backend team |
| mTLS certificates | Short-lived certs (7 day validity); CA bundle | Backend team |
| GPG infrastructure | Key generation, storage of public keys, signature verification | Backend team |
| Admin workstation | Secure system for generating GPG keys and enrollment QRs | Admin
|-------------|-------------|-------|
| Cryptic staging server | mTLS endpoint, test users, seeded messages | Backend team |
| mTLS certificates | Client certs for each test user; CA bundle | Backend team |
| Erlang crypto vectors | Exported test fixtures for parity validation | Backend team |
| Signing vault | Android keystore, iOS certs, GPG key for checksums | Release engineering |
| CI runners | macOS for iOS builds; Linux for Android/web | DevOps |
| Device farm (optional) | Physical Android/iOS devices for smoke tests | QA |

---

## 5. Validation & QA Strategy

### 5.1 Test Coverage Targets

| Layer | Target Coverage | Key Focus |
|-------|-----------------|-----------|
| `data/crypto` | ≥95% | All code paths, edge cases, Erlang parity |
| `data/engine` | ≥90% | State transitions, error handling |
| `data/network` | ≥80% | Connection states, protocol parsing |
| `data/storage` | ≥85% | CRUD, encryption, migrations |
| `presentation` | ≥70% | Widget render, provider integration |

### 5.2 Test Categories

| Category | Scope | Examples |
|----------|-------|----------|
| **Unit** | Isolated classes | X3DH key derivation, ratchet encrypt/decrypt, DAO operations |
| **Integration** | Multiple layers | Engine handshake with fake repos, storage recovery after restart |
| **Widget** | UI components | Message bubble rendering, settings toggle state |
| **End-to-End** | Full app on device | Two-device chat, offline queue flush, passphrase reset |
| **Security** | Threat scenarios | Tampered ciphertext rejection, cert pinning bypass attempt, DB inspection after logout |

### 5.3 Manual QA Checklist

- [ ] Fresh install → setup → first message sent/received
- [ ] Kill app mid-ratchet → restart → session intact
- [ ] Airplane mode → queue messages → reconnect → flush
- [ ] Wrong passphrase → lockout behavior
- [ ] Key fingerprint verification via QR code
- [ ] Delete conversation → verify DB purged
- [ ] App update → sessions preserved

---

## 6. Risk & Mitigation
| **GPG enrollment UX** | High | Medium | Clear admin docs; test QR scanning in various lighting; fallback manual import |
| **Cert renewal failure** | Medium | High | Robust retry with backoff; user notification; manual renewal option |

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Cryptography drift** | Medium | High | Maintain Erlang parity test suite; run cross-client compatibility weekly |
| **Key leakage** | Low | Critical | Enforce secure storage APIs; clear memory after use; threat model review M7 |
| **mTLS complexity** | Medium | Medium | Abstract behind `mtls_config.dart`; test on multiple OS versions early |
| **Network instability** | High | Medium | Robust reconnect/backoff; offline queue; clear UI feedback |
| **Platform divergence** | Medium | Medium | Platform channels for cert storage; test Android + iOS in parallel |
| **Timeline creep** | Medium | Medium | Timebox milestones; bi-weekly demos; cut scope before quality |
| **Dependency CVE** | Low | High | Pin versions; run `pub outdated` + CVE scan in CI |

---

## 7. Deliverables Checklist

### 7.GPG enrollment flow (QR scanner, key import, cert request)
- [ ] Automatic certificate renewal with retry logic
- [ ] Admin tooling (GPG key generation, enrollment QR creation)
- [ ] Server enrollment/renewal endpoints with signature verification
- [ ] Secure key storage (identity keys, GPG

- [ ] Architecture-compliant project skeleton (`lib/core`, `lib/data`, `lib/domain`, `lib/presentation`)
- [ ] Crypto primitives with Erlang-vector unit tests
- [ ] X3DH engine (initiator + responder flows)
- [ ] Double Ratchet engine (DH ratchet, chain advancement, skipped keys)
- [ ] mTLS WADMIN-ENROLLMENT.md` – admin guide for creating enrollment QRs
- [ ] `docs/ENROLLMENT-PROTOCOL.md` – QR format spec, encryption schema
- [ ] `docs/KEY-ROTATION.md` – GPG key rotation and revocation process
- [ ] `docs/ebSocket client with reconnect, heartbeat, offline queue
- [ ] Protocol encoder/decoder for all message types
- [ ] Secure key storage (identity keys, certs)
- [ ] Encrypted SQLite database with DAOs
- [ ] `CrypticEngine` orchestrator with Riverpod providers
- [ ] Complete UI screens per architecture doc
- [ ] Dark/light theming, accessibility labels

### 7.2 Documentation

- [ ] `README.md` – quick start, building, running
- [ ] `docs/INSTALL.md` – end-user installation guide
- [ ] `docs/SECURITY-REVIEW.md` – threat model, findings, mitigations
- [ ] Inline Dartdoc for public APIs

### 7.3 Release Assets
enrollment API implementation | Backend team | Day 2 |
| 4 | Design and spec enrollment QR code format | Mobile + Backend | Day 3 |
| 5 | Set up admin GPG key generation tooling | Backend team | Week 2 |
| 6 | Export Erlang crypto test vectors | Backend team | Day 3 |
| 7 | Add core dependencies to `pubspec.yaml` (including `openpgp`, `mobile_scanner`) | Mobile dev | Day 3 |
| 8 | Set up project board with milestones & tasks | PM | Day 1 |
| 9 ] F-Droid repository metadata (if open-sourcing)
- [ ] Version API endpoint for in-app updates
9. Enrollment Implementation Roadmap

This section provides a step-by-step guide for implementing the hybrid GPG enrollment approach (Option 3).

### Phase 1: Admin Tooling (Weeks 11–12)

**Goal**: Enable administrators to generate enrollment packages for new users.

#### Week 11: Core Tooling
1. **Day 1-2**: Extend cryptic-onboard for admin enrollment
   - Add `create-enrollment` subcommand to `cryptic/bin/cryptic-onboard`
   - Modify `generate_gpg_key()` to support batch/non-interactive mode
   - Add parameters: `--username`, `--server`, `--output-dir`
   - Test: Generate keys for test users, verify with `gpg --import`

2. **Day 3-4**: Enrollment package encryption
   - Add `create_enrollment_package()` function to cryptic-onboard
   - Define JSON schema for enrollment data
   - Implement encryption using `openssl enc -chacha20-poly1305` and `argon2`
   - Add `--passphrase` option (prompt or from stdin)
   - Test: Encrypt/decrypt with various passphrases

3. **Day 5**: QR code generation
   - Add QR code generation using `qrencode` command
   - Generate QR codes from encrypted JSON (version 40-L)
   - Export as PNG for printing (default: `<username>_enrollment.png`)
   - Test: Scan generated QR with phone camera app

#### Week 12: Batch Processing & Documentation
1. **Day 1-2**: Batch enrollment tool
   - Add `batch-enroll` subcommand to cryptic-onboard
   - CSV input: username, passphrase hint
   - Generate multiple enrollment packages
   - Create HTML page with embedded QR codes for printing

2. **Day 3**: Admin documentation
   - Write `docs/ADMIN-ENROLLMENT.md`
   - Document dependencies (curl, openssl, gpg, jq, qrencode, argon2)
   - Provide usage examples and security best practices
   - Create troubleshooting guide

3. **Day 4-5**: Testing & validation
   - Integration test: Generate enrollment → scan → verify decryption
   - Security review of admin tooling
   - Test with various passphrases and server configurations
   - Prepare demo for mobile team

### Phase 2: Server Implementation (Week 12–13)

**Goal**: Add enrollment and renewal endpoints with GPG signature verification.

#### Week 12: Enrollment Endpoint
1. **Day 1-2**: Database schema
   - Add `enrollment_tokens` table (token, username, expires_at, used)
   - Add `user_gpg_keys` table (username, key_id, public_key)
   - Migration scripts

2. **Day 3-4**: Enrollment handler
   - Create `apps/cryptic_server/src/cryptic_enroll_handler.erl`
   - Parse incoming enrollment request
   - Validate enrollment token (not expired, not used)
   - Verify GPG signature on CSR
   - Issue short-lived certificate (7 days)
   - Store user account and GPG public key

3. **Day 5**: Token management
   - API for admin to generate enrollment tokens
   - Token expiry logic (48 hours)
   - Rate limiting (5 attempts per token)

#### Week 13: Renewal Endpoint
1. **Day 1-2**: Renewal handler
   - Create `apps/cryptic_server/src/cryptic_renew_handler.erl`
   - Validate existing certificate (not expired, matches username)
   - Verify GPG signature on new CSR
   - Issue renewed certificate with same Ed25519 keys

2. **Day 3**: Revocation mechanism
   - Admin API to revoke GPG keys
   - Server rejects requests signed with revoked keys
   - Logging and alerting

3. **Day 4-5**: Integration testing
   - End-to-end test: Enroll → renew → revoke
   - Performance test: 100 concurrent enrollments
   - Security audit

### Phase 3: Mobile Implementation (Week 13)

**Goal**: Implement QR scanning, key import, and certificate management in Flutter app.

#### Week 13: Enrollment Flow
1. **Day 1**: Dependencies and UI scaffold
   - Add `mobile_scanner: ^3.5.0` and `openpgp: ^2.0.0` to `pubspec.yaml`
   - Create enrollment screens directory structure
   - Design UI mockups

2. **Day 2**: QR scanner
   - Implement `QRScannerScreen` with camera preview
   - Handle permissions (camera)
   - Parse QR code data and validate format

3. **Day 3**: Decryption and parsing
   - Implement `EnrollmentParser` class
   - Passphrase input UI
   - Decrypt payload with Argon2id + ChaCha20-Poly1305
   - Validate JSON schema

4. **Day 4**: Key import and CSR signing
   - Parse PGP armored keys using `openpgp` package
   - Store GPG keys in `flutter_secure_storage`
   - Generate Ed25519 identity keys
   - Create and sign CSR with GPG key

5. **Day 5**: Certificate request and finalization
   - Upload signed CSR to enrollment endpoint
   - Store received certificate
   - Complete enrollment flow
   - Navigate to main app

### Phase 4: Certificate Renewal (Week 14)

**Goal**: Implement automatic certificate renewal background task.

#### Week 14: Renewal Implementation
1. **Day 1-2**: Renewal scheduler
   - Create `CertificateRenewalScheduler` class
   - Periodic check (every 6 hours)
   - Trigger renewal when <2 days until expiry

2. **Day 3**: Renewal logic
   - Generate new CSR with existing Ed25519 keys
   - Sign CSR with stored GPG key
   - Upload to renewal endpoint
   - Replace old certificate

3. **Day 4**: Error handling
   - Retry logic with exponential backoff
   - User notification for repeated failures
   - Manual renewal option in settings

4. **Day 5**: Testing
   - Unit tests for renewal scheduler
   - Integration test: Mock time, verify renewal triggered
   - Test offline handling (queue renewal)

### Phase 5: Integration & Testing (Week 15)

**Goal**: End-to-end validation and security hardening.

#### Week 15: Full Validation
1. **Day 1**: Admin flow testing
   - Generate enrollment package
   - Print QR code
   - Test with multiple passphrases

2. **Day 2**: Mobile enrollment testing
   - Scan QR code in various conditions
   - Test wrong passphrase, expired token
   - Verify keys stored securely

3. **Day 3**: Renewal testing
   - Advance time to trigger renewal
   - Test renewal with/without network
   - Verify certificate replaced

4. **Day 4**: Security audit
   - Penetration testing (tampered QR, MITM)
   - Verify no key leakage in logs
   - Test revocation mechanism

5. **Day 5**: Documentation
   - Write `docs/ENROLLMENT-PROTOCOL.md`
   - Update user guide with enrollment instructions
   - Create demo video for admins

---

## 
---

## 8. Next Actions (Kickoff Week)

| # | Action | Owner | Due |
|---|--------|-------|-----|
| 1 | Create Flutter project scaffold with architecture folders | Mobile dev | Day 1 |
| 2 | Configure CI workflow (lint, test, build) | Mobile dev | Day 2 |
| 3 | Request staging server access + mTLS certs | Backend team | Day 2 |
| 4 | Export Erlang crypto test vectors | Backend team | Day 3 |
| 5 | Add core dependencies to `pubspec.yaml` | Mobile dev | Day 3 |
| 6 | Set up project board with milestones & tasks | PM | Day 1 |
| 7 | Schedule bi-weekly demo cadence | PM | Day 1 |

---

## Appendix A: Local Development Environment Setup

This section covers how to set up a local development environment and run the app in simulators/emulators for rapid iteration.

### A.1 Prerequisites

| Tool | Version | Installation |
|------|---------|--------------|
| Flutter SDK | ≥3.16.0 | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| Dart SDK | ≥3.2.0 | Bundled with Flutter |
| Xcode | ≥15.0 | Mac App Store (macOS only, required for iOS) |
| Android Studio | ≥2023.1 | [developer.android.com/studio](https://developer.android.com/studio) |
| CocoaPods | ≥1.14.0 | `sudo gem install cocoapods` (macOS) |

Verify installation:
```bash
flutter doctor -v
```
All checkmarks should be green for your target platforms.

### A.2 iOS Simulator (macOS only)

```bash
# List available iOS simulators
xcrun simctl list devices available

# Boot a specific simulator (e.g., iPhone 15 Pro)
xcrun simctl boot "iPhone 15 Pro"

# Or simply open Simulator app (boots last used device)
open -a Simulator

# Run the Flutter app on iOS Simulator
cd cryptic_app
flutter run -d iPhone

# Run on a specific simulator by device ID
flutter run -d <device-id>
```

**Tips:**
- Use `Cmd + Shift + H` for home button
- Use `Cmd + K` to toggle software keyboard
- Use `Cmd + S` to take a screenshot
- Device logs: `xcrun simctl spawn booted log stream`

### A.3 Android Emulator

```bash
# List existing AVDs (Android Virtual Devices)
flutter emulators

# Create a new AVD via Android Studio:
#   Tools → Device Manager → Create Device
#   Recommended: Pixel 7, API 34 (Android 14), x86_64

# Launch an emulator
flutter emulators --launch <emulator-name>
# Example: flutter emulators --launch Pixel_7_API_34

# Or launch via command line
emulator -avd Pixel_7_API_34

# Run the Flutter app on Android emulator
flutter run -d android
```

**Tips:**
- Enable hardware acceleration (HAXM on Intel, Hypervisor on Apple Silicon)
- Use `Cmd + M` (macOS) or `Ctrl + M` (Windows/Linux) to open dev menu
- Cold boot: `emulator -avd <name> -no-snapshot-load`

### A.4 Web Browser (Quick UI Testing)

```bash
# Run in Chrome
flutter run -d chrome

# Run in Edge
flutter run -d edge

# Run with specific port
flutter run -d chrome --web-port=8080
```

**Note:** Web is useful for rapid UI iteration but:
- mTLS/`SecureSocket` not available in browser
- `flutter_secure_storage` uses localStorage fallback (not secure)
- Use only for layout/widget development, not crypto testing

### A.5 Physical Devices

```bash
# List all connected devices
flutter devices

# Run on a specific physical device
flutter run -d <device-id>

# Release mode for performance testing
flutter run --release -d <device-id>
```

**Android:**
1. Enable Developer Options: Settings → About Phone → Tap "Build number" 7 times
2. Enable USB Debugging: Settings → Developer Options → USB Debugging
3. Connect via USB and accept the debug prompt

**iOS:**
1. Connect device via USB
2. Trust the computer on the device
3. In Xcode: Window → Devices and Simulators → Verify device appears
4. First run requires signing: open `ios/Runner.xcworkspace`, set Team in Signing & Capabilities

### A.6 Hot Reload & Hot Restart

While the app is running in debug mode:

| Command | Shortcut | Effect |
|---------|----------|--------|
| Hot Reload | `r` | Injects code changes, preserves state (~1s) |
| Hot Restart | `R` | Full restart, resets state (~2s) |
| Quit | `q` | Stop the app |
| Detach | `d` | Leave app running, detach debugger |

Hot Reload works for:
- Widget `build()` method changes
- Adding/modifying UI elements
- Changing styles and layouts

Hot Reload does **not** work for:
- `main()` or `initState()` changes
- Static field initializers
- Native code changes
- Adding new dependencies

### A.7 Debugging Tools

```bash
# Open Flutter DevTools (browser-based)
flutter run -d <device>
# Then press `d` or run:
dart devtools

# Inspect widget tree
# In DevTools → Flutter Inspector tab

# Performance profiling
flutter run --profile -d <device>

# Verbose logging
flutter run -v
```

**VS Code:**
- Install "Flutter" extension
- Set breakpoints in `.dart` files
- F5 to start debugging
- Use Debug Console for expressions

**Android Studio:**
- Flutter plugin provides integrated debugging
- Use "Flutter Inspector" tool window
- "Flutter Performance" for frame analysis

### A.8 Running Tests Locally

```bash
# Run all unit and widget tests
flutter test

# Run with coverage
flutter test --coverage

# Run a specific test file
flutter test test/unit/crypto/x3dh_test.dart

# Run integration tests on device
flutter test integration_test/app_test.dart -d <device>

# Run with verbose output
flutter test -v
```

### A.9 Multi-Device Testing

For testing message exchange between two clients:

```bash
# Terminal 1: Run on iOS Simulator
flutter run -d iPhone

# Terminal 2: Run on Android Emulator
flutter run -d android

# Both connect to same staging server
# Test X3DH handshake and message flow
```

### A.10 Common Issues & Fixes

| Issue | Solution |
|-------|----------|
| iOS Simulator not found | `xcode-select --install` then restart |
| Android emulator slow | Enable hardware acceleration; use x86_64 image |
| `CocoaPods not installed` | `sudo gem install cocoapods && pod setup` |
| Gradle build fails | `cd android && ./gradlew clean` |
| iOS build fails | `cd ios && rm -rf Pods Podfile.lock && pod install` |
| Hot reload not working | Restart the app with `R` (hot restart) |
| Device not detected | Check USB cable; run `flutter doctor` |

---

## Appendix B: Key File Mapping (Erlang → Dart)

| Erlang Module | Dart Equivalent | Notes |
|---------------|-----------------|-------|
| `cryptic_engine.erl` | `lib/data/engine/cryptic_engine.dart` | Central orchestrator |
| `cryptic_ws_client.erl` | `lib/data/network/websocket/websocket_client.dart` | mTLS WebSocket |
| `cryptic_double_ratchet.erl` | `lib/data/crypto/ratchet/double_ratchet.dart` | Session state, encrypt/decrypt |
| `cryptic_lib.erl` (X3DH) | `lib/data/crypto/x3dh/x3dh_engine.dart` | Key agreement |
| `cryptic_event_bus.erl` | Riverpod `StreamProvider`s | Pub/sub via streams |
| `cryptic_console_callbacks.erl` | Repository implementations | Storage callbacks |

---

## Appendix C: Protocol Message Types

| Type | Direction | Purpose |
|------|-----------|---------|
| `welcome` | Server → Client | Connection established |
| `users` | Server → Client | List of registered users |
| `key_bundle` | Server → Client | Peer's X3DH prekey bundle |
| `x3dh` | Bidirectional | Initial encrypted message (X3DH) |
| `ratchet` | Bidirectional | Subsequent encrypted message (Double Ratchet) |
| `message_sent` | Server → Client | Delivery acknowledgment |
| `error` | Server → Client | Error response |
| `user_status` | Server → Client | Online/offline notification |
| `upload_identity_keys` | Client → Server | Register identity keys |
| `upload_prekey_bundle` | Client → Server | Upload one-time prekeys |
| `get_key_bundle` | Client → Server | Request peer's keys |
| `list_users` | Client → Server | Request user list |

---

## Appendix D: Security Checklist

- [ ] Keys never logged or exposed in error messages
- [ ] Database encrypted at rest with user-derived key
- [ ] mTLS CA pinned; no system trust store fallback
- [ ] Plaintext cleared from memory after encryption
- [ ] Biometric unlock optional, not default
- [ ] Root/jailbreak detection with user warning
- [ ] ProGuard/R8 obfuscation enabled for release
- [ ] No analytics or tracking SDKs
