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
