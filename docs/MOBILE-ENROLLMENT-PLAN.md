# Mobile Enrollment Plan — Ed25519 Approach

> **Version**: 1.1  
> **Date**: April 2026  
> **Status**: Implemented (Phase 1–3 complete, Phase 4 pending)  
> **Related**: [`FLUTTER-ARCHITECTURE.md`](./FLUTTER-ARCHITECTURE.md),
> [`AGENTS.md`](../AGENTS.md)

## 1. Background

The Cryptic mobile app (Flutter) has working end-to-end encrypted messaging:
X3DH key agreement, Double Ratchet, mTLS WebSocket transport, and a chat UI
that interoperates with the Cryptic server. The remaining blocker is
**onboarding**: how a new mobile client obtains its mTLS certificate.

The existing PC client flow relies on GPG:

1. Admin generates a GPG keypair for the user and registers the public key
   on the server.
2. User creates a CSR, signs it with the GPG private key, and submits to
   `POST /ca/v1/csr`.
3. Server verifies the GPG detached signature and issues an X.509 certificate.

This does not translate well to mobile:

- **No mature Dart OpenPGP library** — the `openpgp` package is unmaintained
  and signature format compatibility with `erl_gpg` is unverified.
- **GPG key material is large** — armored public + private keys are ~2–4 KB,
  pushing the encrypted QR payload beyond the maximum QR code capacity
  (~2,953 bytes for Version 40-L). The existing test enrollment file
  (`dave_mobile_enrollment.txt`) is 5,640 bytes — it never would have fit
  in a QR code.

## 2. Proposed Solution: Ed25519 Enrollment

Replace GPG with raw Ed25519 signatures for mobile enrollment. The trust
model is identical — admin generates a keypair, pre-registers the public
half on the server, and the mobile client proves possession of the private
half by signing a CSR. Only the cryptographic format changes.

### Why Ed25519

| Aspect | GPG | Ed25519 |
|--------|-----|---------|
| Dart support | No mature library | Already implemented (`pointycastle`) |
| Erlang verification | `erl_gpg` (external dep) | `public_key:verify/4` (OTP built-in) |
| Private key size | ~1.7 KB armored | 64 bytes raw |
| Signature size | ~200+ bytes (OpenPGP packet) | 64 bytes |
| QR payload | ~5.6 KB (does not fit) | ~650 bytes (fits V15-L) |
| Trust model | Admin registers public key | Identical |

## 3. Enrollment Lifecycle

### 3.1 Admin Creates Enrollment Package

Run on a trusted admin workstation:

```bash
./cryptic/bin/cryptic-onboard create-mobile-enrollment \
  --username dave \
  --server cryptic.example.com \
  --port 8443 \
  --passphrase "hand-this-to-dave-securely"
```

Steps performed by the script:

1. **Generate an Ed25519 keypair** (the "enrollment key").
2. **Compute the enrollment fingerprint**: SHA-256 hash of the 32-byte
   public key, hex-encoded (64 chars). This serves the same role as the GPG
   fingerprint.
3. **Register the public key and fingerprint** on the server via a new admin
   API endpoint (`POST /ca/v1/admin/register-enrollment`), associating it
   with the username.
4. **Fetch the CA certificate fingerprint**: `GET /ca/v1/ca-cert`, compute
   SHA-256 of certificate, take hex digest. This is included in the QR
   for pinning, avoiding embedding the full PEM.
5. **Build the plaintext enrollment payload** (see Section 4.1).
6. **Encrypt** with AES-256-CBC, key derived from passphrase via Argon2id,
   authenticated with HMAC-SHA256 (same scheme as existing enrollment).
7. **Encode as QR code** (PNG image).

Outputs:
- QR code image file (`dave_enrollment.png`)
- JSON file (`dave_enrollment.json`) as backup
- Passphrase (admin delivers separately to user)

### 3.2 Mobile Client Scans QR Code

On first launch, the app presents a "Scan Enrollment QR" screen.

```
┌─────────────────────────────────────┐
│          Welcome to Cryptic         │
│                                     │
│   Scan the enrollment QR code       │
│   provided by your administrator    │
│                                     │
│   ┌─────────────────────────────┐   │
│   │                             │   │
│   │     [ Camera Preview ]      │   │
│   │                             │   │
│   │     ┌───────────────┐       │   │
│   │     │   QR Target   │       │   │
│   │     └───────────────┘       │   │
│   │                             │   │
│   └─────────────────────────────┘   │
│                                     │
│   [ Enter code manually ]           │
│                                     │
└─────────────────────────────────────┘
```

### 3.3 Decrypt & Extract

After scanning:

1. **Prompt for passphrase** — the one the admin provided out-of-band.
2. **Derive keys** from passphrase + salt via Argon2id → 64 bytes:
   - ENC_KEY (32 bytes) for AES-256-CBC decryption
   - HMAC_KEY (32 bytes) for HMAC verification
3. **Verify HMAC** over ciphertext — reject if tampered.
4. **Decrypt** ciphertext with AES-256-CBC using ENC_KEY + IV.
5. **Parse JSON** — extract username, server config, enrollment secret key,
   CA fingerprint, expiry.
6. **Validate expiry** — reject if `expires_at < now`.

### 3.4 Verify CA Certificate

Before submitting anything to the server, establish trust in the CA:

1. **Fetch CA cert** from `GET https://{host}:{port}/ca/v1/ca-cert`
   (accept any TLS cert for this single bootstrap request).
2. **Compute SHA-256** of the received certificate DER bytes.
3. **Compare with `ca_fp`** from the QR payload — abort if mismatch.
4. **Store verified CA cert** in secure storage for all future connections.

This provides MITM protection equivalent to embedding the full cert, using
only 64 hex characters in the QR.

### 3.5 Generate TLS Key & CSR

> **Implementation note (April 2026)**: ECDSA P-256 was chosen for the TLS
> client certificate. Ed25519 was attempted first but failed with
> `NO_COMMON_SIGNATURE_ALGORITHMS` during mTLS handshake — BoringSSL (used
> by Dart/Flutter on iOS) does not support Ed25519 client certificates in
> TLS 1.3. P-256 has universal support across BoringSSL, OpenSSL, and
> Erlang OTP SSL.

1. **Generate an ECDSA P-256 keypair** for the mTLS certificate.
2. **Build a PKCS#10 CSR**:
   - Subject: `CN=dave`
   - Public key: the TLS public key from step 1
   - Self-signed with the TLS private key (standard CSR requirement)
3. **PEM-encode** the CSR.

### 3.6 Sign CSR with Enrollment Key

This is the step that proves identity — replacing GPG signing:

```dart
final csrPemBytes = utf8.encode(csrPem);
final signature = ed25519Service.sign(csrPemBytes, enrollmentSecretKey);
final signatureB64 = base64.encode(signature);
```

The enrollment fingerprint is computed from the public key:

```dart
final enrollmentPubKey = enrollmentSecretKey.sublist(32); // last 32 bytes
final fpBytes = sha256.convert(enrollmentPubKey).bytes;
final enrollmentFp = hex.encode(fpBytes);
```

### 3.7 Submit CSR to Server

```
POST https://{host}:{port}/ca/v1/mobile-csr
Content-Type: application/json

{
  "csr_pem":           "-----BEGIN CERTIFICATE REQUEST-----\n...",
  "enrollment_fp":     "a1b2c3d4...  (64 hex chars)",
  "enrollment_sig_b64": "base64(64-byte Ed25519 signature over CSR PEM)"
}
```

### 3.8 Server Processes Request

New handler: `cryptic_ca_mobile_handler.erl`

1. **Rate limit** per enrollment fingerprint (reuse `cryptic_ca_rate_limiter`).
2. **Look up enrollment identity** in DB by fingerprint — retrieve stored
   Ed25519 public key and verify status is `active`.
3. **Verify Ed25519 signature** over the CSR PEM bytes:
   ```erlang
   EnrollmentSig = base64:decode(SigB64),
   true = public_key:verify(
       CsrPemBytes, none, EnrollmentSig,
       {ed_pub, ed25519, EnrollmentPubKey}
   )
   ```
   No external dependencies — uses OTP's built-in `public_key` module.
4. **Validate CSR** — decode PEM, verify self-signature, extract public key.
5. **Issue X.509 certificate** (reuse `cryptic_ca_cert:issue_from_csr/4`).
6. **Mark enrollment identity** as consumed (or keep active for renewals —
   see Section 6).
7. **Audit log** the issuance event.
8. **Return certificate**:
   ```json
   {
     "status": "issued",
     "cert_pem": "-----BEGIN CERTIFICATE-----\n...",
     "serial": "0x01AB...",
     "expires_at": 1757376000,
     "issued_at": 1744358400,
     "validity_days": 150
   }
   ```

### 3.9 Mobile Stores Certificate & Connects

1. **Store** mTLS certificate + private key in `flutter_secure_storage`
   (existing `CertificateStorageService`).
2. **Store** the verified CA cert.
3. **Securely erase** the enrollment secret key from memory — it is no
   longer needed (see Section 6 for renewal design).
4. **Connect** via mTLS WebSocket — the existing connection flow handles
   this.
5. **Generate X3DH identity keys** and upload to server.
6. **User is online and can chat.**

## 4. Payload Formats

### 4.1 Enrollment Plaintext (before encryption)

> **Implementation note**: The `cryptic-onboard` tool generates verbose
> field names rather than the compact format originally planned. The mobile
> app parses both formats, but the server currently produces only the
> verbose format shown below.

**Actual server format (verbose):**

```json
{
  "version": 2,
  "username": "dave",
  "server_host": "cryptic.example.com",
  "server_port": 8443,
  "enrollment_sec": "<base64 — 48-byte Ed25519 secret key in DER PKCS#8>",
  "enrollment_pub": "<base64 — 32-byte Ed25519 public key>",
  "ca_fingerprint": "<64 hex chars — SHA-256 of CA certificate DER>",
  "expires_at": 1749600000
}
```

**Originally planned format (compact):**

```json
{
  "v": 2,
  "u": "dave",
  "s": { "h": "cryptic.example.com", "p": 8443 },
  "ek": "<base64, 88 chars — 64-byte Ed25519 secret key>",
  "cf": "<64 hex chars — SHA-256 of CA certificate DER>",
  "x": 1749600000
}
```

| Field (verbose) | Field (compact) | Description | Size |
|-----------------|-----------------|-------------|------|
| `version` | `v` | Payload version (2 = Ed25519 mobile) | 1 byte |
| `username` | `u` | Username | variable |
| `server_host` | `s.h` | Server hostname | variable |
| `server_port` | `s.p` | Server port | 2–5 chars |
| `enrollment_sec` | `ek` | Ed25519 secret key (DER PKCS#8 or raw 64 bytes) | 64–88 chars |
| `enrollment_pub` | — | Ed25519 public key (32 bytes, base64) | 44 chars |
| `ca_fingerprint` | `cf` | CA certificate SHA-256 fingerprint (hex) | 64 chars |
| `expires_at` | `x` | Expiry, Unix timestamp | 10 chars |

Estimated plaintext size: **~400–500 bytes** (verbose) / **~300–350 bytes** (compact).

### 4.2 Encrypted QR Payload

> **Implementation note**: The server uses `ct` for the ciphertext field
> (not `ciphertext`). The mobile app recognizes `ct`.

```json
{
  "v": 2,
  "salt": "<32 hex chars>",
  "iv": "<32 hex chars>",
  "ct": "<base64 of AES-256-CBC encrypted plaintext>",
  "hmac": "<64 hex chars — HMAC-SHA256 over ciphertext>"
}
```

Estimated total size: **~650 bytes** — fits in QR Version 15-L (758 byte
capacity). This produces a compact, easily scannable code.

### 4.3 Comparison with Existing GPG Enrollment

| | GPG (v1) | Ed25519 (v2) |
|---|----------|--------------|
| Plaintext size | ~3,500 bytes | ~340 bytes |
| Encrypted size | ~5,640 bytes | ~650 bytes |
| Max QR capacity | 2,953 bytes | 2,953 bytes |
| Fits in QR? | **No** | **Yes (V15-L)** |

## 5. Server-Side Changes

### 5.1 New Database Table: `enrollment_identities`

Parallel to the existing `gpg_identity` table, storing Ed25519 enrollment
keys:

```sql
CREATE TABLE enrollment_identities (
    enrollment_fp   TEXT PRIMARY KEY,      -- SHA-256 of public key (hex)
    enrollment_pub  BLOB NOT NULL,         -- 32-byte Ed25519 public key
    username        TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'active',
                                            -- 'active' | 'consumed' | 'suspended' | 'revoked'
    registered_by   TEXT,                   -- admin identifier
    registered_at   INTEGER NOT NULL,       -- Unix timestamp
    consumed_at     INTEGER,                -- when first cert was issued
    last_seen       INTEGER,
    metadata        TEXT                    -- JSON
);
```

### 5.2 New Erlang Record

In `include/cryptic_ca.hrl`:

```erlang
-record(enrollment_identity, {
    enrollment_fp   :: binary(),           %% SHA-256 hex of public key
    enrollment_pub  :: binary(),           %% 32-byte raw Ed25519 public key
    username        :: binary(),
    status          :: binary(),           %% <<"active">> | <<"consumed">> | ...
    registered_by   :: binary() | undefined,
    registered_at   :: non_neg_integer(),
    consumed_at     :: non_neg_integer() | undefined,
    last_seen       :: non_neg_integer() | undefined,
    metadata        :: binary() | undefined
}).
```

### 5.3 New REST Endpoints

#### `POST /ca/v1/mobile-csr` — Mobile Certificate Request

Handler: `cryptic_ca_mobile_handler.erl`

**Request:**
```json
{
  "csr_pem": "-----BEGIN CERTIFICATE REQUEST-----\n...",
  "enrollment_fp": "a1b2c3d4...",
  "enrollment_sig_b64": "base64(...)"
}
```

**Processing:** Rate limit → lookup identity → verify Ed25519 signature →
validate CSR → issue certificate → audit log.

**Response (success):**
```json
{
  "status": "issued",
  "cert_pem": "-----BEGIN CERTIFICATE-----\n...",
  "serial": "0x01AB...",
  "expires_at": 1757376000,
  "issued_at": 1744358400,
  "validity_days": 150
}
```

**Error responses:**

| HTTP | Code | Condition |
|------|------|-----------|
| 429 | `rate_limited` | Too many attempts |
| 404 | `identity_not_found` | Fingerprint not registered |
| 403 | `identity_consumed` | Already used (if one-time) |
| 403 | `identity_suspended` | Admin suspended |
| 403 | `identity_revoked` | Admin revoked |
| 401 | `signature_invalid` | Ed25519 signature verification failed |
| 400 | `csr_invalid` | Malformed CSR |
| 500 | `issuance_failed` | Internal error |

#### `POST /ca/v1/admin/register-enrollment` — Admin: Register Enrollment Key

Called by the `cryptic-onboard` script during enrollment package creation.
Authenticated via admin mTLS certificate.

**Request:**
```json
{
  "enrollment_fp": "a1b2c3d4...",
  "enrollment_pub_b64": "base64(32-byte public key)",
  "username": "dave"
}
```

**Response:**
```json
{
  "status": "registered",
  "enrollment_fp": "a1b2c3d4...",
  "username": "dave"
}
```

### 5.4 Cowboy Route Registration

Add to existing route configuration:

```erlang
{"/ca/v1/mobile-csr", cryptic_ca_mobile_handler,
    #{operation => mobile_csr}},
{"/ca/v1/admin/register-enrollment", cryptic_ca_admin_handler,
    #{operation => register_enrollment}}
```

### 5.5 Existing Infrastructure Reused

| Component | Reused for |
|-----------|-----------|
| `cryptic_ca_cert:issue_from_csr/4` | Certificate issuance |
| `cryptic_ca_rate_limiter` | Per-fingerprint rate limiting |
| `cryptic_ca_store` | Extended with enrollment identity CRUD |
| `cryptic_ca_serial` | Serial number generation |
| Audit log infrastructure | Logging enrollment events |

## 6. Certificate Renewal

Certificates are short-lived. Renewal should not require the enrollment key
(allowing it to be erased after first use).

**Approach**: Renew via existing mTLS session. If the client holds a valid
(not-yet-expired) certificate, the server issues a fresh one authenticated
solely by the mTLS connection.

### 6.1 Renewal Endpoint

```
POST /ca/v1/renew
Content-Type: application/json

(mTLS-authenticated — no additional signature needed)

{
  "csr_pem": "-----BEGIN CERTIFICATE REQUEST-----\n..."
}
```

**Server processing:**

1. Extract client identity from mTLS certificate (CN = username).
2. Verify the existing certificate is valid and not revoked.
3. Validate the new CSR.
4. Issue a fresh certificate.
5. Return the new cert in the same response format as initial enrollment.

### 6.2 Mobile Renewal Scheduler

The app runs a background check (existing `CertificateRenewalScheduler`
pattern):

1. On app start and periodically (e.g., every 6 hours), check cert expiry.
2. If less than 2 days remaining, trigger renewal.
3. Generate new CSR with existing TLS keypair.
4. Submit to `/ca/v1/renew` over the existing mTLS connection.
5. Store new certificate, reconnect WebSocket.
6. Retry with exponential backoff on failure.
7. Alert user if renewal fails within 24 hours of expiry.

## 7. Admin Tooling Changes

### 7.1 Modify `cryptic-onboard`

Add `create-mobile-enrollment` subcommand (extend the existing
`create-enrollment` or replace it):

**Key differences from existing `create-enrollment`:**

| Step | Current (GPG) | New (Ed25519) |
|------|--------------|---------------|
| Key generation | `gpg --quick-gen-key` | `openssl genpkey -algorithm ed25519` |
| Public key export | `gpg --armor --export` | Raw 32-byte public key, base64 |
| Private key export | `gpg --armor --export-secret-keys` | Raw 64-byte secret key, base64 |
| Key registration | Admin imports GPG pub into server | `POST /ca/v1/admin/register-enrollment` |
| CA cert handling | Full PEM in payload | Fetch + SHA-256 fingerprint only |
| Payload version | `"v": 1` | `"v": 2` |

**Dependencies:** Drop `gpg` dependency for mobile enrollment. Keep
`qrencode`, `argon2`, `openssl`, `jq`, `curl`.

### 7.2 Batch Enrollment

Extend existing `batch-enroll` to support the new format:

```bash
./cryptic/bin/cryptic-onboard batch-mobile-enroll \
  --csv users.csv \
  --server cryptic.example.com \
  --output-dir ./enrollment_packages/
```

CSV format: `username,passphrase`

Outputs per user: `{username}_enrollment.png` + `{username}_enrollment.json`

## 8. Mobile Implementation

### 8.1 New Dependencies

```yaml
# pubspec.yaml additions
dependencies:
  mobile_scanner: ^7.2.0    # QR code scanning (camera, Apple Vision API)
  pointycastle: ^3.9.0      # ECDSA P-256 keypair + CSR ASN.1 encoding
```

> **Implementation note**: `mobile_scanner` was upgraded from v6 to v7
> because v6 depended on Google MLKit which does not support arm64 iOS
> simulators. v7 uses Apple's native Vision API instead. iOS deployment
> target was raised to 16.0 for compatibility.

`Argon2` support via `cryptography` package (already a dependency).

### 8.2 New Files

```
lib/
├── data/
│   └── enrollment/
│       ├── enrollment_service.dart       # Orchestrates the full flow
│       ├── enrollment_payload.dart       # Payload model & JSON parsing
│       ├── enrollment_crypto.dart        # Decrypt QR, sign CSR
│       └── csr_generator.dart            # PKCS#10 CSR creation
│
└── presentation/
    └── screens/
        └── enrollment/
            ├── qr_scanner_screen.dart    # Camera + QR scanning
            ├── passphrase_screen.dart    # Passphrase input
            └── enrollment_progress_screen.dart  # Status during enrollment
```

### 8.3 State Machine

```
┌──────────┐   scan    ┌────────────┐  passphrase  ┌────────────┐
│  Welcome  │────────>│  QR Scanned │────────────>│ Decrypting  │
└──────────┘          └────────────┘              └─────┬──────┘
                                                        │
         ┌──────────────────────────────────────────────┘
         │ success
         ▼
┌────────────────┐  fetch   ┌───────────────┐  match   ┌──────────────┐
│ Verifying CA   │────────>│ CA Fetched     │────────>│ Generating   │
│ Fingerprint    │         │ Checking Hash  │         │ Keys + CSR   │
└────────────────┘         └───────────────┘          └──────┬───────┘
                                                             │
         ┌───────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐  submit  ┌──────────────┐  store   ┌───────────┐
│ Signing CSR     │────────>│ Awaiting Cert │────────>│ Connecting │
│ (Ed25519)       │         │ from Server   │         │ WebSocket  │
└─────────────────┘         └──────────────┘          └─────┬─────┘
                                                            │
                                                            ▼
                                                    ┌──────────────┐
                                                    │   Complete    │
                                                    │  (Chat ready) │
                                                    └──────────────┘

Any state may transition to:
┌─────────┐
│  Error  │──> [ Retry ] or [ Back to Welcome ]
└─────────┘
```

### 8.4 Enrollment Service (pseudo-code)

```dart
class EnrollmentService {
  Future<EnrollmentResult> enroll(String qrData, String passphrase) async {
    // 1. Parse encrypted envelope
    final envelope = EnrollmentEnvelope.fromJson(qrData);
    if (envelope.version != 2) throw UnsupportedVersionError();

    // 2. Decrypt
    final payload = await _decrypt(envelope, passphrase);

    // 3. Check expiry
    if (payload.expiresAt.isBefore(DateTime.now())) {
      throw EnrollmentExpiredError();
    }

    // 4. Verify CA certificate
    final caCert = await _fetchAndVerifyCaCert(
      payload.serverHost, payload.serverPort, payload.caFingerprint,
    );

    // 5. Generate TLS keypair + CSR
    final tlsKeyPair = generateRSAKeyPair();
    final csrPem = generateCSR(
      keyPair: tlsKeyPair,
      commonName: payload.username,
    );

    // 6. Sign CSR with enrollment key
    final signature = ed25519.sign(
      utf8.encode(csrPem),
      payload.enrollmentSecretKey,
    );

    // 7. Submit to server
    final response = await submitMobileCsr(
      serverHost: payload.serverHost,
      serverPort: payload.serverPort,
      caCert: caCert,
      csrPem: csrPem,
      enrollmentFp: computeFingerprint(payload.enrollmentSecretKey),
      signatureB64: base64.encode(signature),
    );

    // 8. Store certificate
    await certificateStorage.storeCertificate(
      certPem: response.certPem,
      keyPem: tlsKeyPair.privatePem,
      caCertPem: caCert,
      username: payload.username,
      serverHost: payload.serverHost,
      serverPort: payload.serverPort,
    );

    // 9. Erase enrollment key from memory
    payload.enrollmentSecretKey.fillRange(0, 64, 0);

    return EnrollmentResult.success(
      username: payload.username,
      serverHost: payload.serverHost,
      serverPort: payload.serverPort,
    );
  }
}
```

## 9. Security Analysis

### 9.1 Trust Model

The trust anchor is the admin workstation:

1. Admin generates the enrollment key on a trusted machine.
2. Admin registers the public half on the server (via admin mTLS cert).
3. Admin encrypts the private half and delivers via QR + passphrase.

An attacker must compromise **both** the QR code **and** the passphrase to
impersonate a user. The QR is typically shown in person; the passphrase is
communicated separately.

### 9.2 Threat Analysis

| Threat | Mitigation |
|--------|-----------|
| QR code photographed by attacker | Encrypted with Argon2id-derived key; useless without passphrase |
| Passphrase intercepted | Useless without the QR ciphertext |
| Both QR + passphrase compromised | Enrollment fingerprint is one-time use; server rejects re-enrollment |
| MITM during CA cert fetch | CA fingerprint in QR (out-of-band) detects substitution |
| MITM during CSR submission | CSR submitted over TLS using verified CA cert |
| Replay of old enrollment | Expiry timestamp checked; enrollment marked consumed on server |
| Brute-force passphrase | Argon2id with high cost parameters; rate limiting on server |
| Enrollment key on device | Erased from memory after certificate is obtained |
| Certificate theft from device | Short-lived certs; revocation via admin API |

### 9.3 Improvements Over GPG Approach

- **Smaller attack surface**: Ed25519 is a single, well-audited primitive
  vs. the full OpenPGP format with its complexity.
- **No external dependencies**: Server uses OTP built-in `public_key`
  module; no `erl_gpg` NIF needed for mobile enrollment.
- **Constant-time verification**: Ed25519 verification is constant-time
  by design.
- **Smaller QR code**: Easier to scan, works with lower-resolution cameras.

## 10. Implementation Phases

### Phase 1: Server Endpoints (Erlang) — COMPLETE ✓

1. ✅ Add `enrollment_identity` record to `cryptic_ca.hrl`
2. ✅ Add `enrollment_identities` table creation to `cryptic_ca_store.erl`
3. ✅ Implement CRUD operations in `cryptic_ca_store.erl`
4. ✅ Create `cryptic_ca_mobile_handler.erl` for `POST /ca/v1/mobile-csr`
5. ✅ Add admin registration endpoint for enrollment keys
6. ✅ Register new routes in Cowboy configuration
7. Unit tests for signature verification and enrollment flow (not yet added)

**Server-side fixes applied during integration:**
- `cryptic_ca_cert.erl`: Fixed `extract_public_key_for_verification/1` to
  return `{ed_pub, ed25519, PublicKey}` format required by
  `public_key:verify/4`.
- `cryptic_ca_cert.erl`: Fixed `convert_subject_pk_info/1` for Ed25519
  to set parameters to `asn1_NOVALUE` (absent per RFC 8410) instead of
  `{namedCurve, OID}` which caused an ASN.1 encoder `case_clause` crash.

### Phase 2: Admin Tooling (Shell Script) — COMPLETE ✓

1. ✅ `cryptic-onboard` generates v2 QR codes with Ed25519 enrollment keys
2. ✅ Ed25519 key generation via `openssl genpkey -algorithm ed25519`
3. ✅ CA fingerprint fetching and embedding
4. ✅ Server registration via admin API
5. ✅ QR generation with the v2 payload format
6. ✅ Tested: generate enrollment → scan QR → decrypt → enroll → chat

**Note**: The tool outputs verbose field names in the encrypted payload
(e.g., `enrollment_sec` instead of `ek`). See Section 4.1.

### Phase 3: Mobile Enrollment (Flutter) — COMPLETE ✓

1. ✅ Add `mobile_scanner` v7.2.0 dependency (Apple Vision API)
2. ✅ Implement `enrollment_payload.dart` (verbose field name parsing)
3. ✅ Implement `enrollment_crypto.dart` (Argon2id + AES-256-CBC decrypt,
   HMAC-SHA256 verification, Ed25519 CSR signing)
4. ✅ Implement `csr_generator.dart` (**ECDSA P-256**, not Ed25519/RSA —
   see Section 3.5 note)
5. ✅ Implement `enrollment_service.dart` (orchestrator)
6. ✅ Build enrollment UI screens (QR scanner with clipboard paste fallback,
   passphrase input, step-by-step progress)
7. ✅ Wire into app startup flow (splash → check certs → enrollment or login)
8. ✅ End-to-end tested: admin creates QR → mobile scans → cert issued →
   mTLS connects → send and receive encrypted messages

**Key deviations from plan:**
- TLS client certificate uses **ECDSA P-256** (not RSA-2048 or Ed25519)
  due to mTLS compatibility across TLS stacks.
- QR scanner includes **clipboard paste fallback** for simulator testing
  (camera not available on iOS simulator).
- iOS deployment target raised to **16.0** for mobile_scanner v7.
- `pointycastle` used for manual ASN.1 DER construction of PKCS#10 CSR
  (no library supports ECDSA P-256 CSR generation out of the box in Dart).

### Phase 4: Certificate Renewal — NOT STARTED

1. Add `POST /ca/v1/renew` endpoint to server
2. Implement `CertificateRenewalScheduler` in Flutter app
3. Background renewal with expiry check
4. UI notification for renewal failures
5. Test: issue short-lived cert → wait → verify auto-renewal

## 11. Testing Strategy

| Test Type | Scope | Examples |
|-----------|-------|---------|
| **Unit** | Crypto operations | Ed25519 sign/verify, Argon2id derivation, AES decrypt, CSR generation |
| **Unit** | Payload parsing | v2 format parsing, field validation, expiry check |
| **Integration** | Server endpoint | Submit CSR → receive cert; invalid sig → rejection; rate limiting |
| **Integration** | Full enrollment | QR scan → decrypt → CSR → cert → connect → chat |
| **Security** | Attack scenarios | Wrong passphrase, expired enrollment, tampered QR, replay attack |
| **UX** | Edge cases | Camera permission denied, very long hostname, network timeout during CSR |

## 12. Open Questions

1. **Enrollment key reuse for renewal?** Current plan erases the enrollment
   key and uses mTLS-based renewal. Alternative: keep enrollment key for
   re-enrollment if certificate is lost. Decision: start with erase +
   mTLS renewal; add re-enrollment later if needed.

2. ~~**RSA vs ECDSA for TLS cert?**~~ **RESOLVED**: ECDSA P-256 chosen.
   Ed25519 was attempted but BoringSSL (Flutter/iOS) does not support
   Ed25519 client certificates for mTLS. P-256 works across BoringSSL,
   OpenSSL, and Erlang OTP SSL.

3. **Multiple devices per user?** Each device gets its own enrollment
   package and its own mTLS certificate. The X3DH identity keys are
   per-device. Multi-device sync is a separate future feature.

4. **Backward compatibility?** The server continues supporting GPG
   enrollment (`POST /ca/v1/csr`) for PC clients. The mobile endpoint
   (`POST /ca/v1/mobile-csr`) is additive. ✓ Confirmed working.

## 13. Known Issues & Outstanding Work

### Bugs / Issues

1. **WebSocket disconnects on unhandled session state**: When alice sends a
   ratchet message to rune but no X3DH session has been established (e.g.,
   after a fresh install), the server may close the connection. The mobile
   app should gracefully handle incoming ratchet messages for unknown
   sessions.

2. **Erlang jsx char-list encoding**: The server's `jsx:encode` serializes
   Erlang character lists (e.g., usernames) as JSON integer arrays
   (`[97,108,105,99,101]` for "alice") instead of strings. This was fixed
   in all mobile-side message parsers with a `_asString()` helper, but the
   root cause is on the server side — atom-keyed maps with string values
   should use binaries (`<<"alice">>`) not lists (`"alice"`).

3. **X3DH identity keys regenerated on every launch**: The mobile app
   uploads fresh identity keys and 100 one-time prekeys on each connection.
   This breaks existing sessions with other users. Keys should be persisted
   and only uploaded once (or when the prekey supply is depleted).

### Not Yet Implemented

4. **Certificate renewal** (Phase 4): Short-lived certificates will expire
   and the app has no auto-renewal mechanism yet.

5. **Server-side unit tests**: The enrollment endpoint works but has no
   dedicated test suite.

6. **Compact QR payload format**: The current QR uses verbose field names
   (`enrollment_sec`, `ca_fingerprint`, etc.) producing a larger payload
   than the planned compact format. Consider updating `cryptic-onboard` to
   use compact field names for smaller QR codes.

7. **Error handling for consumed enrollments**: When a user re-enrolls
   after a simulator reset/app reinstall, the server rejects with "identity
   consumed". The admin currently must manually reset the enrollment status
   in the database. Consider adding an admin API to re-activate enrollments.
