---
id: SPEC-firebase-integration
companions:
  - stack.md     # spec-authored — library versions, message-type choice, token schema, ordered setup checklist (fed by the 2026-11-07 RN-Firebase research run)
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate.

# Firebase Integration: Push, Crashlytics, Analytics

## Why

**A pain to solve, plus an opportunity.** Fenzit's installed base (owner + technician phones, Android live on Play as `com.fenzit` v1.2.1) never learns about job assignments, leave decisions, or report events unless the app happens to be foregrounded — notifications travel only via Supabase Realtime to a live socket, so a backgrounded or force-closed app is deaf (the deferred-work ledger's "Revisit when Story 3.4 adds push" note has been open since the notifications epic shipped). Meanwhile the app ships to production with zero crash reporting and zero usage analytics: no way to see a field crash, a funnel drop, or a release's health. Firebase closes both gaps with three free services — FCM, Crashlytics, Analytics — layered on top of the existing Supabase backend without becoming a second backend.

## Capabilities

- **CAP-1 — Device push registration**
  - **intent:** A signed-in app registers its FCM token against its user on the backend — registered at login, re-registered on token rotation, removed at logout — so the server can always target the user's current devices.
  - **success:** A force-closed device with a signed-in user receives a push addressed to that user; after logout, sends to the pruned token stop reaching the device.
- **CAP-2 — Server push fan-out**
  - **intent:** Every notification row `fenzit-be` creates (jobs, leaves, reports) also produces an FCM push to that recipient's registered devices, sent by the backend. Job assignment becomes a notification (user decision, 2026-11-07): creating a job with a technician, or moving a job to a different technician, writes one `job.assigned` row for that technician only — never for the admin who assigned it — so it reaches the bell and the phone like every other row.
  - **success:** Creating one notification row yields a received system push on a force-closed app; a simulated FCM failure leaves the notification row intact and the API response unchanged.
- **CAP-3 — State-aware presentation + deep link**
  - **intent:** Pushes present correctly for every app state — foreground shows in-app without a duplicate system notification, background/quit posts a system notification — and tapping any push lands on the same surface the in-app bell deep-links to.
  - **success:** Tapping a push from a force-closed app opens job detail; the same tap with the app foregrounded does not stack a second notification surface.
- **CAP-4 — Crash reporting**
  - **intent:** Uncaught JS errors and native crashes reach Crashlytics, attributable by app version and build type.
  - **success:** A deliberate test crash from an installed build appears in the Crashlytics console within minutes, tagged with the app version.
- **CAP-5 — Usage analytics**
  - **intent:** A small named event catalog (app open, login, job lifecycle, notification tap) reaches Firebase Analytics so the owner can read funnel health per release.
  - **success:** Each catalog event fires from a device and appears in Analytics DebugView within the session.

## Constraints

- Push is **additive and decoupled**: the notification row remains the source of truth; an FCM send failure must never fail the row insert or the API response (log-only failure).
- Push reaches **exactly the notification's own recipient and never crosses companies**: a row is pushed only to its `user_id`'s tokens, and only while that user is an active, non-disabled member of the row's tenant; a device token belongs to whoever signed in on it last (user requirement, 2026-11-07).
- No Firebase Auth, Firestore, Realtime DB, Remote Config, Storage, or Functions — Supabase auth, Postgres + Realtime, the server-driven config API (SPEC-server-driven-config), and R2 uploads keep owning those layers; Firebase never becomes a second backend.
- No Firebase credentials in the app beyond `google-services.json` (public-by-design client config); service-account / server credentials live only in `fenzit-be`.
- POST_NOTIFICATIONS runtime permission (Android 13+) is requested in context, never at boot; denial degrades to today's in-app-only behavior.
- The Play Data safety form must be updated to disclose FCM/Crashlytics/Analytics collection before the release that first ships them (privacy compliance shipped 2026-11-03).
- bun only; JDK 17 for Android builds; RN 0.87 strict TypeScript API; `@react-native-firebase` pinned to 26.4.1 (TurboModules, New Architecture required, modular API only — v27 is SPM-only while the iOS project builds on CocoaPods; see stack.md).
- User-facing pushes travel as `notification` + small `data` hybrid messages — never data-only (background data-only is deprioritized/dropped; `priority: high` misuse degrades the app instance).
- Backend changes deploy before app changes (cross-repo ordering): token-registration endpoint must exist before a build that sends tokens ships.

## Non-goals

- iOS push delivery in this change — the APNs auth key needs Apple Developer org enrollment. The iOS Firebase app (`com.fenzit`) is already registered and its config file is in place; the remaining iOS checklist lives in [stack.md](stack.md).
- Rich push UX (images, action buttons, grouped stacks) — plain title/body + deep link only.
- In-app notification preference toggles — the OS permission is the only gate.
- FCM topics, segmentation, A/B experiments, or BigQuery export.
- Any migration of auth, data, config, or files to Firebase.

## Success signal

A technician's phone with the app force-closed buzzes with a job-assignment push, and tapping it lands on the job detail; the next release's Crashlytics dashboard shows real crashes by version, and Analytics DebugView shows the login → job flow live.

## Assumptions

- One Firebase app serves all build types — `applicationId` stays `com.fenzit` for debug and release (the documented replace-install workflow depends on it); debug noise is filtered by build type/version in the consoles.
- FCM tokens are tied to the login lifecycle; anonymous/pre-login states never register.
- Every notification event type pushes in v1 — no per-event opt-in list; the OS permission is the only gate.

## Open Questions

- ~~FCM sender credential: now or later?~~ Resolved 2026-11-07: create now — dedicated `fenzit-fcm-sender`, role Firebase Cloud Messaging API Admin only, key kept outside every repo.
- ~~Both roles or owner-only first?~~ Resolved by the Assumptions: every event type pushes to its own recipient in v1, all roles.
- ~~Analytics catalog?~~ Resolved for v1: `app_open`, `login`, `job_created`, `job_step_completed` {step}, `notification_tap` {source, type}; extend per funnel need later.
