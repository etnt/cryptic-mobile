# Plan: Incoming Message Notifications Without Google Play Services

**Status:** Draft · **Date:** 2026-04
**Scope:** Android first (iOS noted at the end — it is a different problem)

---

## 1. Problem

Cryptic is distributed as a side-loaded APK. The phones this app targets do
not have Google Play services, so **FCM (Firebase Cloud Messaging) is not
available** as a push channel. Without FCM there is no system-level way for
the server to "ping" the device.

Today, incoming messages produce notifications via
`lib/data/services/notification_service.dart` (flutter_local_notifications),
but only while the app is in the foreground. The WebSocket lives inside the
Flutter Dart isolate:

- When the user backgrounds the app, Android pauses the isolate and the
  WebSocket goes silent. `_CrypticAppState.didChangeAppLifecycleState` has to
  call `engine.reconnectAfterAppResume()` when the user returns.
- Under memory pressure Android kills the process entirely.

**Result:** messages sent while the app is backgrounded are only seen when
the user reopens the app. No timely notification.

This is exactly the problem Signal and Telegram solve on de-Googled phones:
keep a WebSocket alive around the clock inside a **Foreground Service**.

---

## 2. Chosen Approach: Foreground Service + Persistent WebSocket

A foreground service is an Android component the OS is not allowed to kill
while the user is actively using the phone. In exchange, it must show a
permanent notification in the status bar (e.g. "Cryptic — background
connection enabled").

The service hosts the WebSocket connection (or keeps the Flutter engine
alive to host it) so that:

1. Incoming WebSocket frames arrive within seconds, even with the app in the
   background or the screen off.
2. The app decrypts the message locally (keys never leave the device) and
   posts a local notification.
3. Battery cost rises — the radio and CPU cannot deep-sleep — but that is the
   accepted tradeoff for FCM-free push (see §8).

### Two implementation options

| | Option A: `flutter_foreground_task` package | Option B: Native Kotlin service |
|---|---|---|
| How | Plugin runs the existing Dart code in a background isolate attached to a foreground-service notification | Hand-written `Service` in Kotlin that owns the WebSocket and posts notifications |
| Pros | Reuses existing Dart WebSocket/engine code; single language; faster to ship | Smallest runtime footprint; no Flutter engine overhead while backgrounded; survives Flutter rebuilds |
| Cons | Background isolate keeps a full Flutter engine alive (~50–80 MB RSS); battery cost higher | WebSocket + session/ratchet logic must be re-implemented or bridged in Kotlin (double crypto maintenance) |

**Decision: Option A first.** The engine, ratchet sessions, and encrypted
storage are all Dart. Re-implementing them natively (Option B) would duplicate
the security-critical code. Ship Option A; if battery profiling shows the
Flutter engine overhead is unacceptable, revisit Option B.

---

## 3. Workstream 1 — Foreground service skeleton (Android)

Files touched: `android/app/src/main/AndroidManifest.xml`, new Kotlin files,
new Dart service wrapper.

1. Add manifest permissions:
   - `FOREGROUND_SERVICE`
   - `FOREGROUND_SERVICE_DATA_SYNC` (Android 14+ requires a typed service;
     `dataSync` is the correct type for a messaging connection)
   - `POST_NOTIFICATIONS` (already present)
   - `WAKE_LOCK` (only for brief reconnect attempts, not held continuously)
   - `RECEIVE_BOOT_COMPLETED` (optional phase 5: restart service after reboot)
2. Declare the service in the manifest with
   `android:foregroundServiceType="dataSync"` and `android:stopWithTask="false"`.
3. Start the service when the user logs in (`AuthStatus.isAuthenticated`),
   stop it on logout.
4. Notification setup:
   - New channel `cryptic_connection` with `IMPORTANCE_MIN`/`LOW` so the
     permanent status notification is silent and collapsed at the bottom of
     the shade (this mirrors Signal's "Background connection enabled").
   - Keep the existing `cryptic_messages` channel (`IMPORTANCE_HIGH`) for
     actual incoming messages.
   - Android 13+: the status notification is suppressed until
     `POST_NOTIFICATIONS` is granted — the service still runs; only the icon
     is hidden.

## 4. Workstream 2 — Message handling while backgrounded

Goal: the same `MessageReceived` → save → notify path works with the UI not
visible.

1. Extract the handler in `_CrypticAppState.build` (the
   `engineEventsProvider` listener that persists to `MessageRepository` and
   calls `NotificationService.showMessageNotification`) into a reusable
   listener used by **both** the app state and the background isolate.
2. Ensure the background isolate can access:
   - passphrase-verified `EncryptedSecureStorage` — decide how the passphrase
     is held while backgrounded. **Security note:** keeping the passphrase in
     memory of a long-lived service increases exposure. Mitigation options:
     - Store the derived Argon2id key in the Android Keystore-wrapped
       storage for the service lifetime only, cleared on logout.
     - Or accept the same exposure Signal accepts (decryption keys resident
       while the connection lives). Document the choice.
   - SQLite (`sqflite_sqlcipher`) — must be opened in the background isolate
     before the foreground UI reopens it (check for double-open conflicts).
3. Suppress duplicate work: if the foreground app is visible
   (`activeChatPeer` logic already exists in `NotificationService`), the
   background listener should not double-post.

## 5. Workstream 3 — Connection reliability tuning

Update `ConnectionConfig` defaults used by the background path:

1. Heartbeat: keep 30 s pings; confirm they are WebSocket ping frames (cheap)
   not app-level JSON.
2. Reconnect: unlimited attempts (`maxReconnectAttempts: 0`) while the service
   is alive, capped exponential backoff at 60 s; on Doze-interrupted sleep,
   resume from `initialReconnectDelay`.
3. TCP keepalive / TLS: verify `WebSocketChannel` ping cadence keeps NAT
   mappings alive (typical carrier NAT timeout 5–10 min).
4. Wake lock policy: acquire only for the duration of a reconnect attempt,
   release on success/failure. Never hold across idle periods.

## 6. Workstream 4 — Battery-optimization UX

Android Doze and OEM task killers (Xiaomi, Huawei, etc.) can still throttle
the service. Signal handles this with explicit user education:

1. After login, if battery optimization is not exempted, show a one-time
   screen: "To receive messages in the background, allow Cryptic to run
   unrestricted." with a button opening
   `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (needs the matching manifest
   permission) or the system settings page.
2. Add a Settings entry showing current background-connection state and a
   diagnostic hint per OEM ("On Xiaomi: Settings → Autostart → Cryptic").
3. `diagnostics_provider.dart` is the natural home for a
   "background connection: OK / paused / stopped" indicator.

## 7. Workstream 5 — Lifecycle & polish

1. Reboot persistence: `BootCompletedReceiver` restarts the service if the
   user was logged in (persist a "logged in" flag).
2. Logout: stop service, clear notification channel state.
3. App killed by user (swipe away): with `stopWithTask="false"` the service
   keeps running — verify and document behavior.
4. Server side (Erlang): confirm pending-message delivery is unchanged; the
   client simply connects more of the time, so `pending_messages_delivered`
   should mostly fire on connect.

## 8. Accepted Tradeoffs (document in README)

- **Battery:** the radio and CPU wake regularly for heartbeats; deep sleep is
  prevented while the connection lives. Expect measurable extra drain
  (Signal-class apps: roughly 1–4 %/hour with aggressive tuning, more on
  poor networks). Tuning §5 minimizes this.
- **Big-tech-free:** no Google infrastructure, no third party can see
  connection metadata — consistent with the project's threat model.
- **Status-bar icon:** permanent, silent, dismissible per-channel on Android
  8+; required by the OS as the price of the surviving connection.

## 9. Explicitly Out of Scope (for now)

- **iOS:** no foreground-service equivalent. Without APNs (requires Apple
  developer account + server push integration) background delivery is not
  achievable; background fetch is best-effort only. Revisit separately.
- **UnifiedPush / ntfy:** a community push relay would reduce battery cost
  and is worth a future spike, but adds an extra server component.

## 10. Milestones & Verification

| # | Milestone | Verify |
|---|---|---|
| M1 | Foreground service starts on login, shows silent status notification, stops on logout | Manual + `adb shell dumpsys activity services` |
| M2 | Message received while app backgrounded → notification + persisted message | Two-device test: background app, send from peer, check shade + DB |
| M3 | Screen off / Doze: message arrives within ~60 s with battery exemption; note behavior without it | `adb shell dumpsys battery` unplug test |
| M4 | Reboot → service auto-restarts, pending messages delivered | Reboot test |
| M5 | Battery profiling over 8 h idle | Battery historian; tune heartbeat if drain > target |

**Rollout:** ship M1–M2 behind a Settings toggle ("Keep background connection
on") defaulting ON for new installs, so users on battery-critical devices can
opt out (accepting delayed notifications, which the app already handles via
reconnect-after-resume).
