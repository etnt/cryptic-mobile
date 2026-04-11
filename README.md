# Cryptic Mobile
> Mobile App for the Cryptic e2e encrypted chat system

A Flutter-based mobile client for the [Cryptic](https://github.com/etnt/cryptic)
end-to-end encrypted messaging system. Implements X3DH key agreement and Double
Ratchet protocols for secure communication.

## Status

✅ **M7 Integration Complete** - Bidirectional encrypted messaging working!

| Feature | Status |
|---------|--------|
| X3DH Key Agreement | ✅ Working |
| Double Ratchet Encryption | ✅ Working |
| mTLS WebSocket Connection | ✅ Working |
| Send/Receive Messages | ✅ Working |
| Online Users List | ✅ Working |
| Session Persistence | ✅ Working |
| Mobile Enrollment (QR + Ed25519) | ✅ Working |
| Message History (DB) | 🔄 Pending |

## Mobile Enrollment

New devices are onboarded via QR code scanning — no GPG required on mobile.
An admin generates an enrollment package with the `cryptic-onboard` tool, which
produces an encrypted QR code. The mobile app scans it, decrypts with a
passphrase, and uses the embedded Ed25519 key to authenticate a certificate
signing request.

See [Mobile Enrollment Plan](docs/MOBILE-ENROLLMENT-PLAN.md) for the full
design and protocol details.

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
- Xcode (for iOS development on macOS)
- Android Studio (for Android development)
- Running [Cryptic server](https://github.com/etnt/cryptic) with mTLS enabled

## Quick Start

```bash
# Navigate to the Flutter app
cd cryptic_app

# Install dependencies
flutter pub get

# Run on connected device or simulator
flutter run
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
│   ├── core/           # Config, constants, errors, utilities
│   ├── data/           # Repositories, data sources, DTOs
│   ├── domain/         # Models, services, use cases
│   └── presentation/   # UI (screens, widgets, providers)
├── test/               # Unit tests
└── pubspec.yaml        # Dependencies
```

## Documentation

- [Architecture](docs/FLUTTER-ARCHITECTURE.md) - System design and crypto protocols
- [Implementation Plan](docs/FLUTTER-IMPLEMENTATION-PLAN.md) - Development roadmap
- [Mobile Enrollment Plan](docs/MOBILE-ENROLLMENT-PLAN.md) - QR-based Ed25519 enrollment design
- [Server Agent Guide](AGENTS.md) - Event bus architecture for client integration

## License

See [LICENSE](LICENSE) for details.
