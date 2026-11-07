# stack.md — implementation contract (fed by the 2026-11-07 RN-Firebase research run)

Companion to [SPEC.md](SPEC.md). Versions and claims below were verified against official docs on 2026-11-07; sources inline.

## Versions

| Piece | Version | Note |
|---|---|---|
| `@react-native-firebase/app` / `messaging` / `crashlytics` / `analytics` | **27.1.0** (exact peer match across all four) | TurboModules; New Architecture **required** since v26; namespaced API deleted — modular API only (`getMessaging`, `onMessage`, …) |
| `com.google.gms.google-services` (Gradle) | 4.5.0 | RNFB-pinned |
| `com.google.firebase:firebase-crashlytics-gradle` | 3.0.8 | RNFB-pinned |
| Firebase Android BOM | 35.0.2 | pulled transitively; do not override |
| `firebase-admin` (fenzit-be) | 14.5.0 | needs Node ≥ 22 (Render runtime is fine) |

Fallback pin `26.4.1` exists only for the future iOS-on-CocoaPods decision (see [iOS-later](#ios-later-checklist)).

## Message contract (backend → device)

- **`notification` + small `data` hybrid** — `notification` (title/body) so the OS displays in background/quit at high priority without any JS running; `data` carries `{"type": "<notification_event_type>", "id": "<entity_id>"}` (flat string map, ≤ 4 KB total, keys `from`/`gcm`/`google*` forbidden) for tap deep-linking and foreground routing.
- **Never data-only for user-facing pushes** — background/quit data-only messages are deprioritized unless `priority: high`, and high-priority use that doesn't produce user-visible notifications degrades the app instance after FCM's 7-day behavioural evaluation.
- Foreground: nothing auto-displays; `onMessage` routes to an in-app banner via a **local** notification (display handled by `@notifee/react-native`).
- Per-user targeting by **token, never topic** (topics are for broadcasts only; Google: never a topic per user).

## Device-token lifecycle

Client (`fenzit-app`, all via modular API):
- Post-login and on app start when already signed in: `getToken(messaging)` → POST to backend (idempotent upsert — React 19 StrictMode double-mounts effects in dev, so the server must tolerate duplicate uploads).
- `onTokenRefresh(messaging, token => upload(token))` for rotation.
- Logout: `deleteToken(messaging)` (permanently invalidates the token) → then DELETE on the backend.
- Stay on the token path — RNFB's Firebase-Installation-ID migration (`messaging_installation_id_enabled`) stays off; revisit when it becomes default.

Server (`fenzit-be`):

```sql
CREATE TABLE device_tokens (
  token         TEXT PRIMARY KEY,   -- upsert target (idempotent under StrictMode)
  user_id       UUID NOT NULL,
  platform      TEXT NOT NULL,      -- 'android' | 'ios'
  app_version   TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_failure  TEXT
);
```

- Send: tokens by `user_id` → `sendEachForMulticast` in 500-token chunks (responses stay order-mapped) → delete rows whose response error is `messaging/registration-token-not-registered` or invalid-argument-malformed-token; retry only 429/503 with exponential backoff + jitter (honour `Retry-After`).
- Prune: nightly sweep deletes `last_seen_at` older than 60–90 days (Android expires registrations at 270 days; stale registrations are undeliverable long before).
- Credentials: `GOOGLE_APPLICATION_CREDENTIALS` env/file mount (Google-recommended) pointing at a service account with role **Firebase Cloud Messaging API Admin**; JSON never in git, never in the app bundle.

## Ordered setup checklist

**Phase 0 — Firebase console.** Done 2026-11-07 except the service account: project `fenzit` (number 686145154578, Spark, Google Analytics enabled, FCM API V1 enabled); Android app `1:686145154578:android:9db301800ea51b6ffdf2cb` → `android/app/google-services.json`; iOS app `1:686145154578:ios:53d36d473ca3c75ffdf2cb` → `ios/FenzitApp/GoogleService-Info.plist`. Remaining: the FCM sender service account (dedicated, role *Firebase Cloud Messaging API Admin* only — never a key for the project-wide `firebase-adminsdk-fbsvc` account). SHA-1s optional for these three products but register both debug + release (Play **app signing key** SHA-1 from Play Console → App integrity, not the upload keystore) — free future-proofing since Maps already generates them. All three products are free on Spark; no billing account.

**Phase 1 — Android wiring (fenzit-app).**
1. `bun add` the four RNFB packages.
2. `google-services.json` → `android/app/` (one file covers debug + release; both share `applicationId com.fenzit`).
3. Root `android/build.gradle`: classpaths for google-services 4.5.0 + crashlytics-gradle 3.0.8 (`google()` repo already present).
4. App `build.gradle`: apply `com.google.gms.google-services` **before** `com.google.firebase.crashlytics` — either missing or misordered = startup crash ("No Firebase App '[DEFAULT]'" / "Crashlytics build ID missing").
5. Optional release block: `nativeSymbolUploadEnabled true` for native-frame crashes; R8 mapping upload is automatic; **no extra ProGuard rules**.
6. Project-root `firebase.json`: `messaging_android_notification_channel_id` → a real channel id (RNFB's default channel is "Miscellaneous" — not acceptable UX); disable Crashlytics JS exception-handler chaining (`crashlytics_javascript_exception_handler_chaining_enabled: false`).
7. **Strip AD_ID**: Firebase Analytics auto-merges `com.google.android.gms.permission.AD_ID` into the manifest — remove it and its collection (same `tools:node="remove"` pattern as the existing FGS strip):
```xml
<uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove" />
<meta-data android:name="google_analytics_adid_collection_enabled" android:value="false" />
```
8. `./gradlew clean` after adding plugins, then **verify the merged manifest** (Android Studio Merged Manifest view, or Play App Bundle Explorer after upload) — `tools:node="remove"` is reported to not always apply cleanly in RN builds, and Play blocks releases whose advertising-ID declaration disagrees with the merged manifest.

**Phase 2 — JS integration (fenzit-app).**
1. `index.js`: `setBackgroundMessageHandler(getMessaging(), …)` **before** `AppRegistry` (required, runs as a 60 s headless task, no UI).
2. POST_NOTIFICATIONS via `PermissionsAndroid` on API ≥ 33 — asked in context (first push-relevant moment), never at boot; denial degrades to in-app-only.
3. Foreground: `onMessage` in the root component (unsubscribe on cleanup) → in-app banner via `@notifee/react-native` (also owns channel creation at app start).
4. Deep link: on notification tap (`getInitialNotification` + `onNotificationOpenedApp`), route via the same mechanism the in-app bell uses (Story 3-4 deep links).
5. Token lifecycle calls per the section above.
6. Crashlytics: global JS handler is auto-installed; add `recordError` to the existing error boundary, `log()` breadcrumbs, `setUserId` at login. JS traces in release stay minified (no RN source-map support in Crashlytics) — archive Metro source maps per version for hand-decoding; acceptable to ship.
7. Analytics: auto-collection ships on (sessions, screen_view, notification events); custom events via `logEvent` — params are **not validated** and silently drop when wrong (verify in DebugView: `adb shell setprop debug.firebase.analytics.app com.fenzit`). Respect limits: 500 event names, 25 params/event, name ≤ 40 chars, value ≤ 100 chars.

**Phase 3 — fenzit-be (deploys first — cross-repo ordering).**
1. `bun add firebase-admin`; `FirebaseModule` init once with `applicationDefault()` + project id.
2. `device_tokens` table (Supabase migration) + register/delete endpoints (JWT-auth'd, idempotent upsert).
3. Push hook in the notifications service: after the row insert, fan out `notification+data` per recipient tokens; failures log-only (never fail the insert or the API response).

**Phase 4 — Play disclosure (before the release that first ships these).**
- Advertising ID declaration (App content): **"does not use advertising ID"** — consistent with the AD_ID strip in Phase 1; a mismatch blocks the upload.
- Data safety: Analytics → "Device or other IDs" (app-instance ID only — AAID stripped) + "App interactions", purpose Analytics; Crashlytics → "Diagnostics" + "Device or other IDs" (install UUID), purpose App functionality; FCM → minimal (app version, user agent). All encrypted in transit, not shared beyond subprocessors.
- Privacy policy: add a Firebase/Google section. (DPDP relevance for India users: covered by the policy update.)

## iOS-later checklist

Gated on Apple Developer org enrollment. When it lands: **decide the dependency-manager question first** — RNFB v27 is SPM-only (Firebase Apple SDK ≥ 13 dropped CocoaPods at 12.19.3) and needs `use_frameworks! :linkage => :dynamic`, while RN 0.87 defaults to CocoaPods/static linkage. Either migrate the iOS podfile to RN SPM + dynamic frameworks (keep v27) or pin RNFB `26.4.1` (CocoaPods Firebase 12.19.x). Then (the iOS app is already registered and the plist sits in `ios/FenzitApp/`): add `GoogleService-Info.plist` to the Xcode app target → `FirebaseApp.configure()` in the Swift AppDelegate → Push Notifications capability + Background Modes (remote notifications) → APNs auth key (.p8) uploaded to Firebase → permission via react-native-permissions (RNFB's is a no-op) → physical-device testing only (ARM64 simulator can't register APNs) → dSYM upload is automatic → mirror the data-safety declarations in App Privacy.

## Gotchas (verified 2026-11-07)

- Modular API only — v26 deleted `messaging().onMessage(...)` style calls.
- Plugin presence + order (google-services before crashlytics) — classic startup-crash failure mode.
- Emulators need Google Play services images for FCM/Analytics.
- StrictMode double-mount: idempotent upsert, not ref guards.
- Analytics params silently dropped — always verify in DebugView.
- Leave Google Play **notification delegation** disabled (RNFB default) — incompatible with RNFB listeners.
- v27 runtime message contracts (sound as valid path, `sentTime` epoch-ms) matter only when composing raw Android/iOS configs — the hybrid contract above avoids raw configs.
- Play target API 36 required since Aug 2026 — RN 0.87 aligns; no FCM-specific changes beyond POST_NOTIFICATIONS.
- **AD_ID auto-merge** — Firebase Analytics silently adds the AD_ID permission; strip it and keep the Play advertising-ID declaration at "does not use" ([RNFB #8699](https://github.com/invertase/react-native-firebase/issues/8699), [Play Console: Advertising ID](https://support.google.com/googleplay/android-developer/answer/6048248)).

Sources: [rnfirebase.io](https://rnfirebase.io) (messaging/crashlytics/analytics usage + setups, v26/v27 migration guides, iOS SPM, FAQs, server integration), [Firebase: send messages](https://firebase.google.com/docs/cloud-messaging/send-message), [message priority](https://firebase.google.com/docs/cloud-messaging/android/message-priority), [error codes](https://firebase.google.com/docs/cloud-messaging/error-codes), [manage tokens](https://firebase.google.com/docs/cloud-messaging/manage-tokens), [scale FCM](https://firebase.google.com/docs/cloud-messaging/scale-fcm), [admin setup](https://firebase.google.com/docs/admin/setup), [google-services plugin](https://firebase.google.com/docs/android/google-services-plugin-and-file), [Play data disclosure](https://firebase.google.com/docs/android/play-data-disclosure), [Analytics SDK disclosure](https://support.google.com/analytics/answer/11582702), [Analytics limits](https://support.google.com/analytics/answer/9267744), [pricing](https://firebase.google.com/pricing), [RN 0.87 blog](https://reactnative.dev/blog/2026/08/11/react-native-0.87), [client-auth/SHA-1](https://developers.google.com/android/guides/client-auth), [React StrictMode](https://react.dev/reference/react/StrictMode).
