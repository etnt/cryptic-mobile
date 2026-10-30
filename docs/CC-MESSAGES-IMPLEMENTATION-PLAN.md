# CC Messages: Implementation Plan

Status: Proposed implementation plan. No application changes are included.

## Goal

Add copied text messages through the existing one-to-one encrypted sessions. A user can enter `cc:C` at the end of a message to include C. Each recipient sees the other intended recipients and can choose a private reply or reply-all.

This is a message convention, not a group-encryption protocol. It introduces no server commands, shared group keys, or shared group membership. Existing limitations in peer verification, storage, and delivery remain.

## First-release scope

Include these behaviors:

- Recognize a trailing CC field in outgoing text.
- Show and confirm all recipients before any send.
- Send a separate encrypted text message to each recipient.
- Save each copy in its corresponding one-to-one conversation.
- Offer reply-to-sender and reply-all for incoming CC messages.
- Report failures separately for each recipient.

Exclude these features:

- Dedicated group conversations, membership management, and administrators.
- Attachments with CC recipients.
- Automatic forwarding of received messages.
- Read receipts or proof that another recipient received a copy.
- New cryptographic constructions or changes to the server protocol.
- A durable outbox or automatic retries after an uncertain send.

## Current integration points

The following observations come from source inspection, not runtime testing:

| File | Current behavior | Planned change |
|---|---|---|
| `cryptic_app/lib/presentation/screens/chat_screen.dart` | `_sendMessage` creates one local message and calls the engine. | Delegate validation, confirmation, and multi-recipient sending. |
| `cryptic_app/lib/presentation/widgets/message_input.dart` | Owns its controller and clears text immediately after invoking a synchronous callback. | Support asynchronous preparation, cancellation, and reply drafts without premature clearing. |
| `cryptic_app/lib/data/engine/cryptic_engine.dart` | `sendMessage` encrypts text for one recipient and returns `Future<void>`. | Reuse this interface initially. Do not interpret completion as recipient delivery. |
| `cryptic_app/lib/data/engine/payload_codec.dart` | Text uses ordinary UTF-8 for compatibility. | Preserve the current format. |
| `cryptic_app/lib/presentation/providers/engine_provider.dart` | `usersProvider` combines online users, sessions, and conversation history. | Use this list as recipient candidates, not as proof of identity. |
| `cryptic_app/lib/data/storage/message_database.dart` | Stores messages in separate conversations. | Store each generated text copy without a schema change. |
| `cryptic_app/lib/presentation/widgets/message_bubble.dart` | Displays message content and actions. | Integrate CC context and reply actions without hiding original text. |

The current chat screen uses a local timestamp identifier, while the engine generates transport identifiers separately. This plan does not assume they match.

## Message convention

### Grammar

Recognize one lowercase `cc:` field on the final line, either alone or following a space after the body. Ignore trailing whitespace for recognition. The body must contain non-whitespace text.

The first release supports a comma-separated list with optional ASCII spaces around each name:

```text
Hello, how are you? cc:C
Hello, everyone. cc:C,D
Hello, everyone.
cc:C, D
```

Do not recognize `CC:`, a field embedded in a word, or a field followed by additional body text. Do not search quoted lines or earlier lines for instructions.

Use one shared parser for outgoing preparation and incoming reply suggestions. It returns a body, recipient tokens, and explicit syntax errors. It never sends messages.

Before implementation, inspect the server username rules. Do not invent a client-only restriction on valid accounts. If commas or whitespace are valid username characters, define an unambiguous escaping grammar before shipping.

For an apparent trailing directive with empty recipients or invalid syntax, block sending and explain the problem. Offer an explicit literal-text mode instead of silently sending to only some recipients.

### Literal text

Provide a visible “Send as literal text” choice during preparation. It sends the exact text only to the current peer and ignores all CC instructions.

This choice prevents accidental expansion when someone pastes an example or quotes a message. A receiving client cannot distinguish literal examples from actual copy claims under this text-only convention. It must never forward automatically.

### Recipient rules

The current chat peer is the primary recipient. Resolve CC tokens by exact canonical username within the current account and server.

Apply these rules before confirmation:

- Remove duplicate names while preserving order.
- Exclude the current user's own identity from the recipients.
- Do not send twice when the primary recipient also appears in CC.
- Reject unresolved or ambiguous names without sending any copies.
- Allow known offline contacts. Online status is not a trust decision.
- Limit the first release to five total recipients, including the primary recipient.
- Snapshot the prepared list. If account, server, or recipient resolution changes before sending, require preparation again.

The five-recipient limit is a proposed client limit, not a protocol constraint. Do not silently establish trust in a new identity through CC parsing.

### Per-recipient text

For recipient R, send the body with a canonical suffix listing every intended recipient except R. Do not include the sender in that suffix. If no other recipient remains, omit the suffix.

```text
A composes in the chat with B:
Hello, how are you? cc:C

A sends to B:
Hello, how are you? cc:C

A sends to C:
Hello, how are you? cc:B
```

For three recipients, preserve the prepared order consistently:

```text
Intended recipients: B, C, D

To B: Hello. cc:C,D
To C: Hello. cc:B,D
To D: Hello. cc:B,C
```

Construct copies from the parsed body, not by repeatedly editing a suffix. Encrypt each copy independently through `engine.sendMessage`.

## User interface

### Compose and confirm

When a user presses Send, prepare and validate the message without clearing the composer. For CC sends, show a confirmation with exact usernames and the message body. No network sends occur before confirmation.

Provide these actions:

- Send to the displayed recipients.
- Edit the draft.
- Send the original text literally to the primary recipient only.

Disable repeated submission while preparation or sending is active. Preserve the draft when validation fails or confirmation is canceled. Use mounted checks after asynchronous UI work.

Once confirmed, create one local outgoing message per recipient with the exact text sent to that recipient. Update each conversation through the existing repository and notifier. Do not write directly from widgets to SQL.

Await local persistence before calling the engine for that copy. If persistence fails, do not send that copy. Continue tracking the outcomes for other copies without claiming batch atomicity.

### Incoming messages

Display the original text, including the suffix. Add context such as “Sender also addressed this message to C.” Do not label this as proof of delivery.

Parsing an incoming suffix can create UI suggestions only. It must never trigger a network send, fetch keys, add a trusted contact, or resend a message.

Old clients continue to display ordinary text. Malformed or unsupported incoming suffixes remain visible and do not enable automatic reply-all.

### Replies

“Reply to sender” prepares a draft addressed only to the authenticated transport sender. It does not copy the incoming suffix.

“Reply to all” calculates recipients from the transport sender and the incoming CC list, then removes the current user and duplicates. It opens the sender's one-to-one conversation with an editable CC draft. The normal confirmation applies before sending.

Treat the incoming list as untrusted input. If a listed username is unknown, require explicit resolution or removal before reply-all. Do not silently omit it. The claimed copy list does not prove a shared group or recipient consent.

The first release does not quote the original message automatically. This avoids accidentally treating a quoted suffix as the reply's recipient instruction.

## Sending outcomes and recovery

Use a small application-level coordinator to send the prepared copies sequentially. Record each recipient's local message identifier and attempt outcome independently. Sequential dispatch reduces coordination complexity but does not make delivery atomic.

`engine.sendMessage` can queue work while session establishment proceeds. Its successful return means the call was accepted, not that the server or recipient received the message. Keep existing message-status semantics and do not invent delivery guarantees.

Distinguish at least these outcomes in the batch summary:

- Not attempted, such as after validation or persistence failure.
- Submitted to the engine, with final delivery not established.
- Error during submission, with delivery potentially uncertain.

Do not resend all copies after one error. Do not automatically retry an uncertain copy with a fresh transport identifier. That can duplicate a message and advance the ratchet again.

For this release, offer an explicit “Send again as a new message” action with a duplicate warning where appropriate. Do not label that action a safe retry. Durable, identifier-preserving retries belong to the delivery roadmap.

After partial completion, show a per-recipient summary and preserve access to the original draft. Do not restore a one-click bulk resend that repeats successful submissions. A crash during dispatch can leave only some recipients addressed. State this limitation in user documentation.

## Implementation steps

### 1. Parser and copy builder

Add a pure helper at a proposed path such as `cryptic_app/lib/domain/models/cc_message.dart`. Define parsed text, a prepared recipient list, and generated copies separately.

Test the grammar, canonical suffix construction, deduplication, limits, and literal mode. Keep account lookup outside the parser. No engine or widget imports belong in this helper.

### 2. Send coordinator

Add a proposed application use case at `cryptic_app/lib/domain/usecases/send_cc_message.dart`. Inject recipient resolution, message persistence, and a one-peer sending function. Expose a per-recipient result rather than a single success flag.

Use the authenticated username instead of the current screen's `'me'` placeholder for new outgoing records. Scope all lookups and stored copies to the active account and server. Keep logging free of message bodies.

### 3. Composer and confirmation

Update `message_input.dart` to support awaited submission and externally supplied reply drafts. Define who owns the controller and preserve disposal behavior. Keep ordinary one-recipient messages on the same preparation path without unnecessary confirmation.

Wire `chat_screen.dart` to the coordinator. Preserve text selection, focus, draft text, and accessibility labels through confirmation and errors.

### 4. Incoming context and reply actions

Extend the existing bubble actions, including any long-press menu, without breaking copy, links, or deletion. Add sender-only and reply-all behavior. Navigate using the existing chat route and pass a draft explicitly.

Do not infer a shared conversation identifier from the recipient set. Separate exchanges involving the same people remain ordinary one-to-one chat messages.

### 5. Tests and documentation

Add focused parser, coordinator, widget, and integration tests. Document the syntax, recipient confirmation, partial-send limits, and literal mode in the mobile guide. Test new-to-old client text compatibility.

## Test matrix

| Area | Required cases |
|---|---|
| Parser | One or several names, multiline body, final-line boundary, whitespace, empty body, malformed suffix, uppercase literal, embedded literal. |
| Recipients | Self, primary-peer duplication, repeated names, unknown names, offline known peers, exact case rules, account/server changes, limit exceeded. |
| Copy builder | A/B/C example, four-user example, no remaining CC recipients, deterministic order, no mutation of original body. |
| Consent | Cancel sends nothing, literal mode sends once, recipient preview precedes encryption, rapid taps do not duplicate dispatch. |
| Incoming safety | Receiving a suffix performs no send or key lookup, malformed fields remain text, unknown names do not silently become trusted contacts. |
| Replies | Sender-only clears CC context, reply-all excludes self, validates every recipient, preserves draft on cancel, does not parse quoted history. |
| Failures | Missing engine, persistence error, one recipient errors, queued session setup, uncertain outcome, crash after first submission, no automatic bulk retry. |
| Storage and UI | Copies appear in the correct conversations with exact content, survive restart once stored, and do not overwrite each other. |
| Compatibility | Existing crypto and attachment tests still pass, old clients display suffixes, ordinary text and links remain unchanged. |

## Acceptance criteria

The feature is ready when the A/B/C example works through existing encrypted one-to-one sessions. Every added recipient must appear in a confirmation before sending. No received text can trigger forwarding.

Each generated copy must remain visible in its own conversation. Partial failures must identify the affected recipients without claiming delivery to others. Reply-all must require the same validation and consent as an original CC send.

No crypto primitive, server command, or network payload format change is required. Run `flutter analyze` and the relevant Flutter tests. Manually exercise the flow with three accounts, including one offline recipient and one forced failure.

## Security and product limits

The suffix records the sender's intended recipients, not proof that copies arrived. A modified client can make a false claim. A recipient can copy or forward plaintext independently of this feature.

The server still observes routing metadata. The feature inherits the security of existing peer sessions and identity handling. It does not provide group membership consistency, group removal, or Signal-equivalent security guarantees.

Before coding, approve the username grammar, five-recipient limit, confirmation behavior, and non-durable sending limits. If durable delivery is required for launch, implement the outbox roadmap first rather than imply that this convention supplies it.
