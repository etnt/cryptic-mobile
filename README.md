# Cryptic Mobile

A Flutter client for the [Cryptic](https://github.com/etnt/cryptic) encrypted chat system. The app uses X3DH key agreement, Double Ratchet encryption, and a mutual TLS WebSocket connection.

This is educational software. Nobody audited it for security. You use it at your own risk.

## Features

- X3DH key agreement
- Double Ratchet encryption
- Mutual TLS WebSocket with ECDSA P-256 client certificates
- Enrollment with a QR code and an Ed25519 signature
- Key storage encrypted with Argon2id and AES-256-CBC
- Online user list
- Session persistence
- Notifications for incoming messages on Android, also while the app is in the background (see [Background message connection](#background-message-connection-tradeoffs))
- Tappable links in chat messages: tap an `http` or `https` link to open it in the browser, or long-press it to copy it

Pending work: certificate renewal and on-device message history.

## Install

Download the latest `.apk` file from the release page. Install it on your phone.

## Enrollment

New devices enroll with a QR code. No GPG key is needed on the device.

An admin creates an enrollment package with `cryptic-onboard`. You scan the QR code with the app. The app decrypts the package with the admin passphrase and asks the server for a certificate. You then set a personal passphrase. The passphrase encrypts all key material at rest with Argon2id and AES-256-CBC. The app asks for the passphrase at every login.

See [docs/MOBILE-ENROLLMENT-PLAN.md](docs/MOBILE-ENROLLMENT-PLAN.md) for the full protocol.

## Build yourself

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.2 or newer, a running [Cryptic server](https://github.com/etnt/cryptic), and Xcode or Android Studio.

```bash
cd cryptic_app
flutter pub get
flutter devices
flutter run -d <device-id>
```

On Android, the app changes `localhost` and `127.0.0.1` to `10.0.2.2`. The emulator uses this address to reach the host machine.

For device setup and troubleshooting, see the [mobile app guide](cryptic_app/README.md). The guide covers iOS simulator setup, Android emulator setup, and QR scanner testing on emulators.

## Release builds (signed APKs)

A push of a `v*` tag starts [.github/workflows/release-apk.yml](.github/workflows/release-apk.yml). The workflow builds signed APKs, one universal and one per ABI, and publishes a GitHub release with SHA-256 checksums.

The workflow needs two repository secrets. Set them under Settings, Secrets and variables, Actions:

| Secret | Description |
|--------|-------------|
| `ANDROID_KEYSTORE_BASE64` | base64 text of your release keystore (`.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password. The workflow uses it for the store and the key |

The workflow expects the alias `cryptic` and the same password for the store and the key entry. Generate a keystore, encode it, and then tag a release:

```bash
keytool -genkey -v -keystore cryptic-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias cryptic
base64 -i cryptic-release.jks | pbcopy      # paste into ANDROID_KEYSTORE_BASE64

git tag v1.0.0 && git push origin v1.0.0
```

A local `flutter build apk --release` works without the secrets. The build uses debug signing when `android/key.properties` does not exist.

Note: `applicationId` is still the Flutter template default (`com.example.cryptic_app`). Change it before any Play Store submission.

## Project layout

```
cryptic_app/lib/
  core/          config, errors, utilities
  data/          crypto (X3DH, ratchet), engine, enrollment, network, storage
  domain/        models, use cases
  presentation/  screens, widgets, providers
```

## Documentation

- [Mobile app guide](cryptic_app/README.md): device setup, emulator commands, and troubleshooting
- [Architecture](docs/FLUTTER-ARCHITECTURE.md)
- [Implementation plan](docs/FLUTTER-IMPLEMENTATION-PLAN.md)
- [Mobile enrollment plan](docs/MOBILE-ENROLLMENT-PLAN.md)
- [Server integration guide](AGENTS.md)

## License

See [LICENSE](LICENSE).

## Background message connection (tradeoffs)

Android delivery without Google Play services works by keeping an encrypted
WebSocket alive around the clock inside a foreground service. The service is
a **keep-alive only**: the crypto engine, its WebSocket, and the encrypted
database stay in the UI isolate. There is no second engine and no stored
passphrase. See
[the notification plan](docs/INCOMING-MESSAGE-NOTIFICATION-PLAN.md) for the
full design and verification matrix.

What you see:

- **Notifications:** an incoming message posts a notification, also while the app is in the background. No notification appears for the chat you have open, or while the app is in the foreground, because the message is already on screen.
- **Permission:** turning on "Keep background connection on" in Settings asks for notification permission (Android 13 and newer). Without it, no message notifications appear.
- **Settings:** turn off "Keep background connection on" in Settings to stop the background connection and its status-bar icon. Incoming messages are then delivered only while the app is open.
- **Diagnostics:** the Diagnostics screen shows whether the background connection is running. Notification problems are written to the app's event log.

Accepted tradeoffs:

- **Battery:** the radio and CPU wake regularly for heartbeats; deep sleep is
  prevented while the connection lives. Expect measurable extra drain
  (roughly 1–4 %/hour with aggressive tuning, more on poor networks).
  Users can opt out any time via Settings → "Keep background connection on".
- **Big-tech-free:** no Google infrastructure; no third party sees connection
  metadata — consistent with the project threat model.
- **Status-bar icon:** permanent, silent notification required by Android as
  the price of the surviving connection.
- **Known limitations:** after a device reboot or a force-stop the background
  connection does not restart by itself; the user must re-open the app and
  log in. A swipe-away may also kill the engine even though the service
  survives, because there is no stored credential to rebuild the session.
  Fixing this needs a Keystore-wrapped derived key and a headless engine, so
  it is deferred.
