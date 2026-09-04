# Cryptic Mobile

> Flutter client for the [Cryptic](https://github.com/etnt/cryptic) end-to-end
> encrypted chat system — X3DH key agreement, Double Ratchet, mTLS WebSocket.

**Educational software — not security audited. Use at your own risk.**

## Features

X3DH key agreement · Double Ratchet encryption · mTLS WebSocket (ECDSA P-256
client certs) · QR-based mobile enrollment (Ed25519) · Argon2id-encrypted key
storage · online user list · session persistence.

_Pending: certificate renewal, on-device message history._

## Install

Download and install the latest **.apk** release file, found on the release page.

## Enrollment

New devices onboard via a QR code — no GPG on mobile. An admin creates an
enrollment package with `cryptic-onboard`; the app scans it, decrypts it with the
admin passphrase, and requests an mTLS certificate. You then set a **personal
passphrase** that encrypts all key material at rest (Argon2id + AES-256-CBC) and
is required on every login.

See [docs/MOBILE-ENROLLMENT-PLAN.md](docs/MOBILE-ENROLLMENT-PLAN.md) for the full protocol.

## Build yourself

Requires [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.2, a running
[Cryptic server](https://github.com/etnt/cryptic), and Xcode / Android Studio.

```bash
cd cryptic_app
flutter pub get
flutter devices
flutter run -d <device-id>
```
On Android the app rewrites `localhost` / `127.0.0.1` to `10.0.2.2` automatically
so the emulator can reach the host machine.


## Release builds (signed APKs)

Pushing a `v*` tag triggers
[.github/workflows/release-apk.yml](.github/workflows/release-apk.yml), which
builds signed universal + per-ABI APKs and publishes a GitHub Release with
SHA-256 checksums.

**Required repository secrets** (Settings → Secrets and variables → Actions):

| Secret | Description |
|--------|-------------|
| `ANDROID_KEYSTORE_BASE64` | base64 of your release keystore (`.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore (store) password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

Generate a keystore, encode it, then tag a release:

```bash
keytool -genkey -v -keystore cryptic-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias cryptic
base64 -i cryptic-release.jks | pbcopy      # paste into ANDROID_KEYSTORE_BASE64

git tag v1.0.0 && git push origin v1.0.0
```

Local `flutter build apk --release` still works without secrets — it falls back
to debug signing when no `android/key.properties` is present.

> `applicationId` is still the Flutter template default
> (`com.example.cryptic_app`); change it before any Play Store submission.

## Project layout

```
cryptic_app/lib/
  core/          config, errors, utilities
  data/          crypto (X3DH, ratchet), engine, enrollment, network, storage
  domain/        models, use cases
  presentation/  screens, widgets, providers
```

## Documentation

- [Architecture](docs/FLUTTER-ARCHITECTURE.md)
- [Implementation Plan](docs/FLUTTER-IMPLEMENTATION-PLAN.md)
- [Mobile Enrollment Plan](docs/MOBILE-ENROLLMENT-PLAN.md)
- [Server Integration Guide](AGENTS.md)

## License

See [LICENSE](LICENSE).
