# Cryptic Mobile App

A Flutter client for the Cryptic encrypted messaging system. The app talks to the Cryptic server over mutual TLS and encrypts every message before it leaves the device.

## Features

- End-to-end encryption with X3DH key agreement and the Double Ratchet protocol
- Mutual TLS authentication with client certificates
- Forward secrecy with one-time prekeys
- Key storage in the platform secure storage (iOS Keychain / Android Keystore)
- Passphrase-encrypted keys. The app encrypts all private key material at rest with AES-256-CBC. It derives the AES key from the user passphrase with Argon2id. This adds protection on top of the platform keychain
- Encrypted local database with SQLCipher
- Enrollment with a QR code. You scan a QR code and enter an admin passphrase. The app then creates a certificate and asks you for a personal passphrase. No GPG key is needed on the device
- On startup and app resume, received media older than 30 days can be removed when the media cache exceeds its size limit. Media referenced by recent messages is kept
- On iOS, media uses complete file protection. The app cannot save media while the device is locked, including attachments received in the background

## Prerequisites

- Flutter SDK 3.16.0 or newer
- Xcode 15.0 or newer (for iOS development)
- CocoaPods 1.14.0 or newer

Check your setup with:

```bash
flutter doctor -v
```

## Install dependencies

```bash
cd cryptic_app
flutter pub get
```

## iOS Simulator setup

If the iOS Simulator window does not appear, or it runs without a window, use these commands.

Show the Simulator window frame:

```bash
defaults write com.apple.iphonesimulator ShowChrome -bool true
```

Stop a Simulator that runs without a window:

```bash
killall Simulator 2>/dev/null
```

List the available iOS simulators:

```bash
xcrun simctl list devices available
```

Start a simulator:

```bash
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator
```

If the window still does not appear, start the Simulator app with the device UDID. Get the UDID from the output of `xcrun simctl list devices booted -j`:

```bash
open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app \
  --args -CurrentDeviceUDID $(xcrun simctl list devices booted -j | grep -o '"udid" : "[^"]*"' | head -1 | cut -d'"' -f4)
```

## Android emulator setup

The Android SDK lives at `~/Library/Android/sdk` on macOS. All commands below use this path.

List the available emulators (AVDs):

```bash
~/Library/Android/sdk/emulator/emulator -list-avds
```

Start an emulator. Use an AVD name from the list:

```bash
~/Library/Android/sdk/emulator/emulator -avd Pixel_6a_API34_GoogleAPIs -no-boot-anim &
```

Wait for the boot to finish, and then confirm it:

```bash
~/Library/Android/sdk/platform-tools/adb wait-for-device
~/Library/Android/sdk/platform-tools/adb shell getprop sys.boot_completed
# The command prints 1 when the boot is complete.
```

Stop the emulator:

```bash
~/Library/Android/sdk/platform-tools/adb -s emulator-5554 emu kill
# Replace emulator-5554 with the device name from: adb devices
```

### Create a new emulator

Create an AVD on a Google APIs image. A Google APIs image has Google Play Services, but no Play Store. It is stable for QR scanner testing:

```bash
echo no | ~/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager create avd \
  -n Pixel_6a_API34_GoogleAPIs \
  -k "system-images;android-34;google_apis;arm64-v8a" \
  -d pixel_6a
```

Do not use a system image with `PrivacySandbox` in the name. Its version of Google Play Services (23.18.18) crashes when an app uses ML Kit or Firebase. See Troubleshooting for the symptoms.

### The emulator has no camera

The emulator does not have a real camera. Two options exist for QR enrollment testing:

Paste the QR data. Copy the enrollment QR payload text, then open the QR scanner screen in the app and tap the paste icon in the app bar.

Or show the QR code to the virtual camera. The emulator simulates a camera that points at a 3D room:

1. Create an image file with the enrollment QR code.
2. Open the emulator menu with the three dots, then open Camera.
3. Under Virtual scene images, tap Add image and select the QR code image.
4. Start the scan in the app. Use the camera controls at the side of the emulator to turn the virtual camera toward the image.

## Run the app

List the connected devices:

```bash
flutter devices
```

Run on a device. Use the device ID from the list:

```bash
flutter run -d <device-id>
```

Example for an iOS simulator:

```bash
flutter run -d A2A02E78-F63D-4000-A309-18B0A4FF3351
```

## Certificate setup

You can get certificates in two ways.

### Option A: QR enrollment (recommended for mobile)

An admin creates an enrollment package with `cryptic-onboard create-mobile-enrollment`. On first launch the app shows a QR scanner, then asks for the admin passphrase, then creates a certificate, and then asks you to set a personal passphrase. The admin passphrase is valid for one use. The personal passphrase protects all stored key material from then on.

### Option B: Manual certificate placement

Place pre-existing certificates in:

```
assets/certificates/
├── ca.crt          # CA certificate
├── client.crt      # Client certificate
└── client.key      # Client private key
```

## Development

### Hot reload

While the app runs:

- Press `r` for hot reload. The app keeps its state.
- Press `R` for hot restart. The app loses its state.
- Press `q` to quit.

### Run tests

```bash
# Run all tests
flutter test

# Run one test file
flutter test test/data/network/protocol/client_messages_test.dart

# Run with coverage
flutter test --coverage
```

### Static analysis

```bash
flutter analyze
```

## Architecture

The app follows a clean architecture pattern:

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

### Passphrase-based key encryption

The app encrypts all sensitive stored data with the personal passphrase. This includes identity keys, signed prekeys, one-time prekeys, session states, and the client TLS private key.

1. The app derives a 32-byte AES key from the passphrase with Argon2id. It uses 64 MiB memory, 3 iterations, 4 parallelism, and a random salt per value.
2. The app encrypts the value with AES-256-CBC and PKCS7 padding. It uses a random IV per value.
3. The app stores a verifier at `cryptic_passphrase_verifier`. The verifier is an encrypted magic string. The app checks the passphrase on login with the verifier, and never reads key material for the check.
4. `EncryptedSecureStorage` wraps the platform secure storage. It encrypts on write and decrypts on read for the sensitive keys.

This gives extra protection. Even if an attacker exports the platform keychain, the attacker cannot read the key material without the passphrase.

## iOS media protection

The app uses `FileProtectionType.complete` for media files. This choice provides
protection while the device is locked, but it also means the app cannot create
or save media files while locked. Background attachment receive therefore cannot
save the received media until the device is unlocked.

## Troubleshooting

### iOS simulator problems

The Simulator window is not visible:

```bash
defaults write com.apple.iphonesimulator ShowChrome -bool true
```

Then restart the Simulator app.

The Simulator runs without a window. Kill it, and start it again with an explicit UDID. See iOS Simulator setup above.

No device is found. List the available devices with `xcrun simctl list devices available`.

### Android emulator problems

The app dies when the QR scanner opens. The connection to the device is lost.

Google Play Services on the emulator restarts again and again in a crash loop. Each restart uses memory, until Android kills your app. The crash log shows `com.google.android.gms.persistent` and `java.lang.StackOverflowError`. The crash starts when the app opens the QR scanner, because ML Kit talks to Play Services.

Confirm the problem. Count the fatal exceptions, and then look at the crash log:

```bash
~/Library/Android/sdk/platform-tools/adb logcat -d -b crash | grep -c "FATAL EXCEPTION"
~/Library/Android/sdk/platform-tools/adb logcat -d -b crash
```

Check if Play Services is stable. A stable system has one process with one PID that does not change:

```bash
~/Library/Android/sdk/platform-tools/adb shell ps -A | grep gms
```

Fix 1: Cold boot with wiped data. A snapshot can contain broken state:

```bash
~/Library/Android/sdk/platform-tools/adb -s emulator-5554 emu kill
~/Library/Android/sdk/emulator/emulator @Pixel_6a_API34_GoogleAPIs -no-snapshot -wipe-data
```

Warning: The `-wipe-data` flag deletes all app data on the emulator. You must install the app again.

Fix 2: If the crash continues after a wipe, the system image is broken. Create a new AVD on a Google APIs image. See Create a new emulator above. Then run the app on the new AVD.

### Build problems

CocoaPods is not installed:

```bash
sudo gem install cocoapods && pod setup
```

The iOS build fails:

```bash
cd ios && rm -rf Pods Podfile.lock && pod install
```

Flutter does not find the device. Run `flutter doctor` and fix the reported problems.

## Related documentation

- [Architecture guide](../docs/FLUTTER-ARCHITECTURE.md)
- [Implementation plan](../docs/FLUTTER-IMPLEMENTATION-PLAN.md)
- [Mobile enrollment plan](../docs/MOBILE-ENROLLMENT-PLAN.md)
- [Agent integration guide](../AGENTS.md)

## License

See [LICENSE](../LICENSE) for details.
