# Next Five Features for Cryptic: Revised Report

Revision: 2. This revision replaces the original expert-panel report after a review of the current source code.

Status: Moderator's proposed roadmap following two expert rounds and a source review. The experts supported overlapping themes, but did not unanimously approve this exact set.

Scope: Flutter client (`cryptic_app/`) and Erlang server (`../cryptic`).

## Basis and limits

Four expert subagents discussed security, mobile experience, delivery reliability, and operations in two rounds. The original discussion had a ten-minute limit.

The subsequent review compared their proposals with the current source code. It found existing features that the original report described as missing.

This report reflects source inspection, not runtime tests or a security audit. Existing code does not prove that a feature works under every failure condition. Implementation plans must establish that behavior through tests.

## Corrections to the original report

### Encrypted message history already exists

`cryptic_app/lib/data/storage/message_database.dart` implements SQLCipher-backed messages and conversations, with a schema migration. The authentication provider exposes the database and repository. The chat screen saves messages through that repository.

The README statement that on-device message history is pending is stale. The proposed work is storage hardening and recovery, not a new message-history implementation.

### Acknowledgements and duplicate detection already exist

An acknowledgement tells the sender that a processing step succeeded. The Erlang server retains messages until it receives `message_ack`. Retrieval of pending messages does not remove them from the queue.

Relevant source files are:

- `../cryptic/src/cryptic_ws_handler.erl`: Message retention, acknowledgement handling, and pending-message retrieval.
- `cryptic_app/lib/data/engine/cryptic_engine.dart`: Client acknowledgement transmission.
- `cryptic_app/lib/data/engine/message_processor.dart`: Duplicate detection.
- `cryptic_app/lib/data/storage/secure_storage/key_storage_service.dart`: Stored identifiers for processed messages.

The remaining concern is crash safety. The engine acknowledges successful processing, while a separate event handler saves the message to history. A crash or storage failure between those operations risks message loss.

The original promise of messages sent "exactly once" was too strong. The target is safe retries without duplicate messages appearing in the conversation. A network timeout can leave delivery uncertain, rather than prove failure.

### Both clients use XOR mixing in the ratchet

A ratchet updates encryption keys as a conversation progresses. Dart mixes the root key and Diffie-Hellman output with XOR in `cryptic_app/lib/data/crypto/primitives/kdf_service.dart`.

Erlang also uses XOR mixing in `../cryptic/src/cryptic_double_ratchet.erl`. Its NIF calls libsodium's `crypto_kdf_derive_from_key`. Dart explicitly implements a compatible key derivation function (KDF).

These observations do not prove correctness or compatibility. They do disprove the original premise that XOR mixing is a Dart-only difference. A Dart-only protocol change risks breaking compatibility.

`cryptic_app/test/kdf_interop_test.dart` prints results for manual comparison. It does not assert expected outputs. Automated comparisons remain useful work.

### The storage concerns are supported by the code

`cryptic_app/lib/data/services/passphrase_encryption_service.dart` uses AES-CBC without an authentication tag. A tag detects changes to encrypted data.

`cryptic_app/lib/data/storage/secure_storage/encrypted_secure_storage.dart` returns raw stored data on `FormatException`. This legacy fallback needs a controlled migration and a defined end state.

Exploiting the fallback requires the ability to modify underlying stored values. The review did not demonstrate a remote exploit.

### Android background notifications already exist

The README documents an Android foreground service and incoming-message notifications. Foreground-only operation is not the current baseline.

Three separate topics need separate decisions:

- Existing Android background connection and notifications.
- Recovery after process termination or device reboot.
- Optional APNs or FCM integration.

The current Android design deliberately avoids Google infrastructure. APNs or FCM support needs an explicit product and privacy decision.

### Certificate errors already have explanatory messages

`cryptic_app/lib/data/services/authentication_service.dart` maps certificate expiry and revocation errors to explanatory messages. Proactive expiry warnings and certificate renewal remain proposed work.

Certificate renewal, prekey rotation, account removal, local-data deletion, and diagnostics export are separate projects. Logout must not silently delete keys or message history.

## Revised five features

### 1. Crash-safe delivery and a durable outbox

An outbox holds outgoing messages until delivery reaches a defined state. Make it survive process termination and device restarts. Extend the existing acknowledgement and duplicate-detection code rather than replace it.

Scope:

- Persist outgoing work before reporting that the app accepted it.
- Define states such as queued, sending, server-accepted, recipient-delivered, failed, and delivery-uncertain.
- Distinguish server acceptance from recipient delivery. Do not infer recipient delivery from `message_sent` alone.
- Retain the same message identifier across retries.
- Define how retries preserve encrypted payloads and avoid advancing the ratchet twice for the same send.
- Coordinate received-message persistence, ratchet state, duplicate tracking, and acknowledgement.
- Include attachment chunks and incomplete file transfers in the recovery design.
- Inspect existing queue limits and retention rules before adding new ones.

Acceptance criteria:

- A process restart does not silently discard accepted outgoing work.
- Duplicate delivery does not create duplicate chat messages or unread counts.
- A received message is not acknowledged before the client can recover it from durable storage.
- Tests cover connection loss, process termination, storage failure, replay, and interrupted attachment transfers.

This feature needs a design for operations that currently span secure storage, the message database, and asynchronous events. A single database transaction cannot cover all of those operations without architectural changes.

### 2. Authenticated storage and safe migration

Authenticated encryption detects changes before it returns plaintext. Add a versioned format for sensitive stored values. Replace indefinite plaintext acceptance with an explicit migration path.

Scope:

- Use an established authenticated encryption scheme, such as AES-GCM or ChaCha20-Poly1305.
- Authenticate the format version and bind encrypted values to their storage context where appropriate.
- Define which legacy values the migration accepts. Reject malformed or unsupported values outside that path.
- Make migration resumable after interruption. Do not delete the only usable copy before its replacement is safely stored.
- Review account and server isolation across keys, sessions, processed-message identifiers, and message databases.
- Review database key derivation and passphrase-change recovery. The database already uses SQLCipher and does not need replacement solely to add history.

Acceptance criteria:

- Modified authenticated values fail closed rather than return raw data.
- Legacy migration preserves readable keys, sessions, and messages.
- Interrupted migration can resume without losing the only usable data copy.
- Tests cover wrong passphrases, malformed values, unsupported versions, account isolation, and migration interruption.

This work can start without a ratchet redesign. Changes to storage formats and changes to the network protocol need separate migration plans.

### 3. Automated Erlang–Dart compatibility tests

Make compatibility claims executable. Start with the existing protocol and add fixed expected outputs. Do not replace the protocol merely because old documentation describes different KDFs.

Scope:

- Turn the printed KDF examples into assertions against shared expected outputs.
- Add shared fixtures for initial key agreement, message encryption, and decryption.
- Exercise conversations in both directions between Erlang and Dart clients.
- Cover key changes, skipped messages, duplicate messages, reconnects, and session restoration after restart.
- Run the relevant tests in CI. Provision the Erlang implementation explicitly rather than assume a sibling checkout exists.
- Review session-reset recovery separately. Do not silently discard trusted peer identities or reset sessions after every decryption failure.

Acceptance criteria:

- A change that breaks an expected shared output fails CI.
- End-to-end tests cover more than KDF output alone.
- Failures identify the protocol operation that differs between implementations.

A migration toward Signal-spec behavior remains a separate decision. It needs a protocol review, version negotiation, and a plan for existing clients and sessions. Automated compatibility tests do not constitute a security audit.

### 4. Peer verification and key-change handling

Let users compare contact identities outside the chat connection. Pin the identity accepted for a contact and distinguish it from a manually verified identity. Define what happens when that identity changes.

Scope:

- Define a fingerprint format that binds the relevant identities and protocol context.
- Show a text representation and a QR code for comparison.
- Store the accepted peer identity and its verification state.
- Detect unexpected identity changes before silently replacing trusted values.
- Define whether sending pauses after a key change and how the user accepts a replacement.
- Preserve trust state across ordinary reconnects and session resets.

Acceptance criteria:

- Both implementations produce the same fingerprint for the same defined inputs.
- Tests cover first contact, successful comparison, identity changes, and explicit acceptance of a replacement.
- Reconnecting or resetting a session does not silently mark a new identity as verified.

This feature does not need a new message-history database. It needs durable, correctly scoped peer-trust records. Warnings alone do not replace out-of-band identity comparison.

### 5. Certificate renewal and expiry warnings

Warn users before a certificate expires. Renew certificates without requiring routine manual enrollment. Provide a clear path when renewal is no longer possible.

Scope:

- Read certificate validity dates and show proactive expiry warnings.
- Define a server-authorized renewal protocol and generate a new certificate signing request (CSR) as required.
- Replace stored certificate material safely without losing a usable credential during interruption.
- Keep the existing explanatory TLS errors and test their behavior.
- Provide a re-enrollment path for expired, revoked, or otherwise unusable credentials.
- Keep logout, account removal, credential revocation, and local-data deletion as distinct actions.

Acceptance criteria:

- Short-lived test certificates trigger warnings before expiry.
- Renewal succeeds through the supported client and server flow.
- Interrupted renewal leaves a recoverable credential state.
- Expiry and revocation produce clear recovery instructions without bypassing authentication.

Do not assume that possession of an old or expired certificate automatically authorizes renewal. The server must define and enforce that policy.

## Work order and dependencies

The order above reflects priorities, not a strict dependency chain. Compatibility tests can start immediately and run throughout the other work.

| Work | Dependency or coordination |
|---|---|
| Delivery and outbox | Needs a durable storage and recovery design. Coordinate with storage migration. |
| Storage migration | Can start independently of a network protocol redesign. |
| Compatibility tests | Can start immediately. Gate protocol and ratchet changes with these tests. |
| Peer verification | Needs durable peer-trust records, not a new message-history implementation. |
| Certificate renewal | Needs an agreed server authorization policy and safe credential replacement. |

Do not combine all five features into one release-sized change. Each needs a focused design and independent acceptance tests. The original small, medium, and large estimates lacked enough evidence and are omitted from this revision.

## Follow-up work and deferrals

Prekey replenishment and rotation are the first follow-up. Prekeys let a sender establish a session while the recipient is offline. Inspect current generation, consumption, upload, and rotation behavior before defining missing work.

Rotation must retain old signed-prekey private keys long enough to decrypt delayed messages. It must not immediately discard keys that queued messages still need. If inspection finds imminent prekey exhaustion or message loss, reconsider its priority.

| Topic | Decision |
|---|---|
| Android background notifications | Preserve the existing feature. Test its documented limitations rather than describe it as absent. |
| Recovery after process termination or reboot | Separate design for credential protection and engine startup. Do not assume notification support solves this. |
| APNs or FCM | Defer pending an explicit platform and privacy decision. Do not promise metadata-free push delivery. |
| Biometric unlock | Defer until its relationship to stored keys and account recovery is defined. |
| Auto-lock | Assess separately from biometric convenience. It can reduce exposure on an unattended device. |
| Release pipeline hardening | Plan incremental work separately from these five features. Compatibility tests belong in CI now. |
| Diagnostics export | Inspect the existing diagnostics and copyable event log before proposing new export behavior. Exclude keys and message plaintext. |
| Signal-spec protocol migration | Decide separately after compatibility tests and a coordinated migration design exist. |

## Decisions before implementation

1. Approve or change the revised five-feature set.
2. Define delivery states and the acknowledgement boundary in a short design note.
3. Choose the storage format and a recoverable migration strategy.
4. Add asserted compatibility vectors before changing ratchet behavior.
5. Define peer key-change behavior and certificate renewal authorization.
6. Inspect prekey lifecycle behavior and adjust its priority if needed.
7. Update stale README and architecture statements to match the implementation.

The five features remain proposals, not a security certification or a unanimous panel decision. Source findings guide the next designs. Tests must establish their actual behavior under failure.
