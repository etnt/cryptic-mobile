# Cryptic Mobile
> Mobile App for the Cryptic e2e encrypted chat system

A Flutter-based mobile client for the [Cryptic](https://github.com/etnt/cryptic)
end-to-end encrypted messaging system. Implements X3DH key agreement and Double
Ratchet protocols for secure communication.

## Status

✅ **M8 Mobile Enrollment Complete** — QR-based onboarding, mTLS, and encrypted chat working end-to-end!

| Feature | Status |
|---------|--------|
| X3DH Key Agreement | ✅ Working |
| Double Ratchet Encryption | ✅ Working |
| mTLS WebSocket Connection | ✅ Working (ECDSA P-256 client certs) |
| Send/Receive Messages | ✅ Working |
| Online Users List | ✅ Working |
| Session Persistence | ✅ Working |
| Mobile Enrollment (QR + Ed25519) | ✅ Working |
| Certificate Renewal | 🔄 Pending (Phase 4) |
| Message History (DB) | 🔄 Pending |

## Mobile Enrollment

New devices are onboarded via QR code scanning — no GPG required on mobile.
An admin generates an enrollment package with the `cryptic-onboard` tool, which
produces an encrypted QR code. The mobile app scans it (or pastes from
clipboard on simulators), decrypts with a passphrase, and uses the embedded
Ed25519 key to sign an ECDSA P-256 certificate signing request. The server
issues an mTLS client certificate and the app connects immediately.

See [Mobile Enrollment Plan](docs/MOBILE-ENROLLMENT-PLAN.md) for the full
design, protocol details, and known issues.

### Admin: Create enrollment package

```bash
# Interactive
cd cryptic
./bin/cryptic-onboard create-mobile-enrollment

# Batch
./bin/cryptic-onboard create-mobile-enrollment \
  --username dave --server https://relay.example.com:8443 \
  --passphrase 's3cret' --admin-cert admin.crt --admin-key admin.key \
  --ca-cert ca.crt --batch
```

### Mobile: Scan & enroll

1. Open the Cryptic app (first launch → enrollment screen)
2. Scan the QR code
3. Enter the passphrase
4. The app generates keys, requests a certificate, and connects

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.2.0
- Xcode (for iOS development on macOS) — iOS deployment target 16.0+
- Android Studio (for Android development)
- Running [Cryptic server](https://github.com/etnt/cryptic) with mTLS enabled
- `zbarimg` (optional, for extracting QR data to clipboard during development)

## Quick Start

```bash
# Navigate to the Flutter app
cd cryptic_app

# Install dependencies
flutter pub get

# Run on iOS simulator
flutter run -d <simulator-id> --no-hot

# Or list available devices first
flutter devices
```

### First-time enrollment (iOS Simulator)

Since the iOS simulator has no camera, use the clipboard paste workflow:

```bash
# Extract QR data to clipboard (macOS)
zbarimg --raw -q path/to/enrollment.png | tr -d '\n' | pbcopy

# Then in the app: tap "Paste from Clipboard" → enter passphrase → Enroll
```

## Development Commands

```bash
# List and launch emulators
flutter emulators                                    # List available emulators
flutter emulators --launch <emulator_id>            # Start an emulator
flutter devices                                      # Check connected devices

# Run on specific platform
flutter run -d ios          # iOS Simulator
flutter run -d android      # Android Emulator (must be running)
flutter run -d chrome       # Web browser

# Code quality
flutter analyze             # Static analysis
dart format .               # Format code

# Testing
flutter test                # Run unit tests
flutter test --coverage     # With coverage report

# Build release
flutter build apk           # Android APK
flutter build ios           # iOS (requires signing)
flutter build web           # Web app
```

## Project Structure

```
cryptic_app/
├── lib/
│   ├── core/               # Config, constants, errors, utilities
│   ├── data/
│   │   ├── crypto/         # X3DH, Double Ratchet, key management
│   │   ├── engine/         # CrypticEngine, session management
│   │   ├── enrollment/     # QR enrollment (CSR, crypto, service)
│   │   ├── network/        # WebSocket, protocol codec, mTLS
│   │   ├── services/       # Authentication service
│   │   └── storage/        # Secure storage, key/session repos
│   ├── domain/             # Models, use cases
│   └── presentation/       # UI (screens, widgets, providers)
├── test/                   # Unit tests
└── pubspec.yaml            # Dependencies
```

## Documentation

- [Architecture](docs/FLUTTER-ARCHITECTURE.md) - System design and crypto protocols
- [Implementation Plan](docs/FLUTTER-IMPLEMENTATION-PLAN.md) - Development roadmap
- [Mobile Enrollment Plan](docs/MOBILE-ENROLLMENT-PLAN.md) - QR-based Ed25519 enrollment design
- [Server Agent Guide](AGENTS.md) - Event bus architecture for client integration

## License

See [LICENSE](LICENSE) for details.
