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
| Passphrase-Encrypted Key Storage | ✅ Working |
| Certificate Renewal | 🔄 Pending (Phase 4) |
| Message History (DB) | 🔄 Pending |

## Mobile Enrollment

New devices are onboarded via QR code scanning — no GPG required on mobile.
An admin generates an enrollment package with the `cryptic-onboard` tool, which
produces an encrypted QR code. The mobile app scans it (or pastes from
clipboard on simulators), decrypts with the admin-provided passphrase, and uses
the embedded Ed25519 key to sign an ECDSA P-256 certificate signing request.
The server issues an mTLS client certificate.

After enrollment the user is prompted to **set a personal passphrase**. This
passphrase (different from the one-time admin passphrase) encrypts all stored
private key material (identity keys, prekeys, session states, TLS private key)
using Argon2id + AES-256-CBC. On every subsequent login the passphrase is
required to decrypt the keys before connecting.

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
3. Enter the admin-provided passphrase
4. The app generates keys, requests a certificate, and stores it
5. Choose a **personal passphrase** — this encrypts all key material at rest
6. Log in with your personal passphrase to connect

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

# List available devices
flutter devices

# Run on iOS simulator
flutter run -d <simulator-id> --no-hot

# Run on Android emulator (see below for setup)
flutter run -d emulator-5554
```

### QR Code to Clipboard (for simulators/emulators)

Simulators and emulators have no camera, so extract the QR data to your
macOS clipboard and paste it in the app. Requires `zbarimg` (`brew install zbar`):

```bash
zbarimg --raw -q path/to/enrollment.png | tr -d '\n' | pbcopy
```

Then in the app: tap **"Paste from Clipboard"** → enter the passphrase → **Enroll**.

### Running on iOS Simulator

```bash
# List iOS simulators
xcrun simctl list devices available

# Run
cd cryptic_app
flutter run -d <simulator-id> --no-hot
```

### Running on Android Emulator

1. **Create an emulator** (one-time, via Android Studio or command line):

```bash
# List available system images
~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager --list | grep system-images

# Create an AVD (example with API 35)
~/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager create avd \
  -n cryptic_test -k "system-images;android-35;google_apis;arm64-v8a"
```

2. **Launch the emulator**:

```bash
# Basic launch
~/Library/Android/sdk/emulator/emulator -avd cryptic_test &

# Launch with custom DNS (needed if the emulator can't resolve external hostnames)
~/Library/Android/sdk/emulator/emulator -avd cryptic_test -dns-server 8.8.8.8 &
```

3. **Wait for it to boot**, then verify:

```bash
~/Library/Android/sdk/platform-tools/adb devices
# Should show: emulator-5554  device
```

4. **Build, install, and launch the app**:

```bash
cd cryptic_app

# Option A: flutter run (builds + installs + attaches debugger)
flutter run -d emulator-5554

# Option B: manual build + install (useful when flutter run hangs)
flutter build apk --debug
~/Library/Android/sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-debug.apk
~/Library/Android/sdk/platform-tools/adb shell am start -n com.example.cryptic_app/.MainActivity
```

5. **Enroll** using the clipboard paste workflow described above.

> **Note:** The app automatically rewrites `localhost`/`127.0.0.1` to
> `10.0.2.2` on Android, since the emulator's `localhost` refers to the
> emulator itself, not the host machine.

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

# Run with filtered log output (useful for debugging)
flutter run -d emulator-5554 2>&1 | grep "I/flutter"

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

### Emulator Management

```bash
# List AVDs
~/Library/Android/sdk/emulator/emulator -list-avds

# Start emulator with custom DNS (fixes external hostname resolution)
~/Library/Android/sdk/emulator/emulator -avd <avd_name> -dns-server 8.8.8.8 &

# Stop a running emulator
~/Library/Android/sdk/platform-tools/adb emu kill

# Check emulator connectivity
~/Library/Android/sdk/platform-tools/adb devices
```

### Troubleshooting Connection Issues

If the app fails to connect to the server:

1. **DNS resolution failure** (`Failed host lookup`):
   - Restart the emulator with `-dns-server 8.8.8.8`
   - Or use the server IP address directly in the login screen

2. **Connection refused**:
   - Verify port forwarding (external port → server port 8443)
   - Test from host: `nc -zv <hostname> <port>`
   - Test TLS: `openssl s_client -connect <hostname>:<port>`

3. **TLS/certificate errors**:
   - Re-enroll to get a fresh certificate
   - Ensure the CA cert stored on the device matches the server's CA

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
│   │   ├── services/       # Authentication, passphrase encryption
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
