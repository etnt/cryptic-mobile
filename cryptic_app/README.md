# Cryptic Mobile App

A Flutter-based end-to-end encrypted messaging client for the Cryptic secure messaging system.

## Features

- **End-to-end encryption** using X3DH key agreement and Double Ratchet protocol
- **mTLS authentication** with client certificates
- **Forward secrecy** with one-time prekeys
- **Secure key storage** using platform-native secure storage (iOS Keychain / Android Keystore)
- **Passphrase-encrypted keys** — all private key material is encrypted at rest with AES-256-CBC using an Argon2id-derived key from the user's passphrase, adding defence-in-depth on top of the platform keychain
- **Encrypted local database** using SQLCipher
- **QR-based mobile enrollment** — scan a QR code + passphrase to onboard (no GPG needed on device)

## Prerequisites

- Flutter SDK ≥3.16.0
- Xcode ≥15.0 (for iOS development)
- CocoaPods ≥1.14.0

Verify your setup:
```bash
flutter doctor -v
```

## Getting Started

### 1. Clone and Setup

```bash
cd cryptic_app
flutter pub get
```

### 2. iOS Simulator Setup

If the iOS Simulator window doesn't appear or shows as headless:

```bash
# Fix Simulator chrome visibility
defaults write com.apple.iphonesimulator ShowChrome -bool true

# Kill any existing Simulator
killall Simulator 2>/dev/null

# Boot a specific device
xcrun simctl boot "iPhone 17 Pro"

# Launch Simulator with explicit device UDID
open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app \
  --args -CurrentDeviceUDID $(xcrun simctl list devices booted -j | grep -o '"udid" : "[^"]*"' | head -1 | cut -d'"' -f4)
```

Or use the one-liner to list available simulators and boot one:
```bash
# List available iOS simulators
xcrun simctl list devices available

# Boot and run
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator
```

### 3. Run the App

```bash
# List available devices
flutter devices

# Run on iOS Simulator (use device ID from flutter devices)
flutter run -d <device-id>

# Example with specific iPhone 17 Pro simulator
flutter run -d A2A02E78-F63D-4000-A309-18B0A4FF3351
```

### 4. Certificate Setup

Certificates can be obtained in two ways:

**Option A — QR Enrollment (recommended for mobile):**

An admin creates an enrollment package with `cryptic-onboard create-mobile-enrollment`.
On first launch the app presents a QR scanner → admin passphrase → automatic
certificate generation → **set your own passphrase** → login. The admin
passphrase is ephemeral (used once to decrypt the QR envelope); the personal
passphrase you choose protects all stored key material going forward.

**Option B — Manual certificate placement:**

Place pre-existing certificates in:
```
assets/certificates/
├── ca.crt          # CA certificate
├── client.crt      # Client certificate
└── client.key      # Client private key
```

## Development

### Hot Reload
While the app is running:
- Press `r` for hot reload (preserves state)
- Press `R` for hot restart (resets state)
- Press `q` to quit

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/data/network/protocol/client_messages_test.dart

# Run with coverage
flutter test --coverage
```

### Static Analysis

```bash
flutter analyze
```

## Architecture

The app follows clean architecture principles:

```
lib/
├── core/           # Constants, utilities, theme, DI
├── data/           # Crypto, network, storage implementations
│   ├── crypto/     # X3DH, Double Ratchet, primitives
│   ├── engine/     # CrypticEngine orchestrator
│   ├── enrollment/ # QR enrollment (payload, crypto, CSR, service)
│   ├── network/    # WebSocket client, protocol codec
│   ├── services/   # Authentication, passphrase encryption
│   └── storage/    # Secure storage, SQLCipher database
├── domain/         # Entities, repositories, use cases
└── presentation/   # Screens, widgets, Riverpod providers
```

### Passphrase-Based Key Encryption

All sensitive stored data (identity keys, signed prekeys, one-time prekeys,
session states, and the client TLS private key) is encrypted at rest using
the user's personal passphrase:

1. **Key derivation** — Argon2id (64 MiB memory, 3 iterations, 4 parallelism) derives a 32-byte AES key from the passphrase + a per-value random salt.
2. **Encryption** — AES-256-CBC with PKCS7 padding and a random IV per value.
3. **Verification** — A verifier (encrypted magic string) is stored so the passphrase can be validated on login without exposing key material.
4. **Transparent I/O** — `EncryptedSecureStorage` wraps the platform secure storage, encrypting on write and decrypting on read for designated sensitive keys.

This adds defence-in-depth: even if the platform keychain is exported or
backed up, the key material cannot be read without the user's passphrase.

## Troubleshooting

### Simulator Issues

| Issue | Solution |
|-------|----------|
| Simulator window not visible | Run: `defaults write com.apple.iphonesimulator ShowChrome -bool true` then restart Simulator |
| Simulator running headless | Kill and relaunch with explicit UDID (see above) |
| Device not found | Run `xcrun simctl list devices available` to see available devices |

### Build Issues

| Issue | Solution |
|-------|----------|
| CocoaPods not installed | `sudo gem install cocoapods && pod setup` |
| iOS build fails | `cd ios && rm -rf Pods Podfile.lock && pod install` |
| Flutter not finding device | Run `flutter doctor` and fix any issues |

## Related Documentation

- [Architecture Guide](../docs/FLUTTER-ARCHITECTURE.md)
- [Implementation Plan](../docs/FLUTTER-IMPLEMENTATION-PLAN.md)
- [Mobile Enrollment Plan](../docs/MOBILE-ENROLLMENT-PLAN.md)
- [Agent Integration Guide](../AGENTS.md)

## License

See [LICENSE](../LICENSE) for details.
