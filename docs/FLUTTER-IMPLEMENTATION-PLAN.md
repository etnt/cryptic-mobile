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
| **M7: Integration & Hardening** | Weeks 11–12 | End-to-end integration tests, security review, in-app update mechanism | Two-device chat succeeds; penetration findings triaged; update check wired |
| **M8: Release & Distribution** | Week 13 | Signed builds (APK, IPA), distribution pipeline (self-host, F-Droid), docs | RC signed with checksums; installation docs published; smoke tests on physical devices |

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

### 3.7 Quality & Security (M7)

| Task | Description | Outputs |
|------|-------------|---------|
| Widget tests | Chat screen, contacts screen, settings toggles | `test/widget/*.dart` |
| Integration tests | Full message flow on instrumented device | `test/integration/message_flow_test.dart` |
| Coverage gate | Require >80% line coverage on `data/crypto`, `data/engine` | CI enforced threshold |
| Static analysis | Zero warnings from `flutter analyze` | CI gate |
| Security review | Threat model doc; key storage audit; cert pinning validation; memory clearing | `docs/SECURITY-REVIEW.md` |
| Dependency audit | Run `flutter pub outdated`, check for CVEs | Documented in release notes |
| Update mechanism | Version endpoint fetch, checksum validation, optional force-update | `lib/core/update/update_checker.dart` |

### 3.8 Release Engineering (M8)

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
| `pointycastle: ^3.9.0` | Ed25519, X25519, ChaCha20-Poly1305 | Core crypto |
| `cryptography: ^2.7.0` | HKDF, additional primitives | Supplement pointycastle |
| `web_socket_channel: ^2.4.0` | WebSocket client | mTLS via `SecureSocket` |
| `flutter_secure_storage: ^9.0.0` | Hardware-backed key storage | iOS Keychain / Android Keystore |
| `sqflite_sqlcipher: ^3.0.0` | Encrypted SQLite | Passphrase-derived key |
| `flutter_riverpod: ^2.4.0` | State management | Preferred over Provider |
| `uuid: ^4.2.0` | Message IDs | UUIDv4 |
| `path_provider: ^2.1.0` | File paths | For DB location |
| `logger: ^2.0.0` | Logging | Structured, redacted |
| `intl: ^0.18.0` | Date formatting | i18n ready |

### 4.2 Infrastructure Requirements

| Requirement | Description | Owner |
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

### 7.1 Code Artifacts

- [ ] Architecture-compliant project skeleton (`lib/core`, `lib/data`, `lib/domain`, `lib/presentation`)
- [ ] Crypto primitives with Erlang-vector unit tests
- [ ] X3DH engine (initiator + responder flows)
- [ ] Double Ratchet engine (DH ratchet, chain advancement, skipped keys)
- [ ] mTLS WebSocket client with reconnect, heartbeat, offline queue
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

- [ ] Signed Android APK (arm64, armeabi-v7a)
- [ ] Signed iOS IPA / TestFlight build
- [ ] SHA-256 checksums + GPG signature
- [ ] F-Droid repository metadata (if open-sourcing)
- [ ] Version API endpoint for in-app updates

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
