---
title: 'Firebase integration — push (FCM), Crashlytics, Analytics'
type: 'feature'
ticket: ''
created: '2026-11-07'
status: 'in-progress'
baseline_revision:
  fenzit-meta: '635b2779a8edff2bf7788588639f2f102935f332'
  fenzit-app: '91a42c8de6b122d3a20aaf7e680ca32f714e58f4'
  fenzit-be: 'f7751825ca2be93f2a7202528172c9aef137ff21'
route: 'full'
route_source: 'auto'
review: ''
review_source: ''
lenses_ran: []
review_loop_iteration: 0
context:
  - '{project-root}/CLAUDE.md'
  - '{project-root}/artifacts/specs/spec-firebase-integration/SPEC.md'
  - '{project-root}/artifacts/specs/spec-firebase-integration/stack.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Notifications reach a phone only over a live Realtime socket, so a backgrounded or force-closed app never hears about jobs, leave or reports; production also ships with no crash reporting and no usage analytics.

**Approach:** Add `@react-native-firebase` 26.4.1 (messaging, crashlytics, analytics) to fenzit-app on both platforms, register FCM tokens per user in a new fenzit-be `device_tokens` table, and have fenzit-be push every new notification row through firebase-admin by sweeping the `pushed_at` outbox column the notifications table already reserves.

## Boundaries & Constraints

**Always:**
- The notification row stays the source of truth; a push failure never fails an insert or an API response (log only).
- Hybrid messages only: `notification` {title, body} + `data` {type: event_type, id: job_id ?? entity_id} (strings). Target users by token.
- Never cross-tenant (user requirement, 2026-11-07): a row is pushed only to tokens of its own `user_id`, and only while that user is an active, non-disabled member of the row's tenant — a push never reaches anyone the bell would not show it to right now.
- A token belongs to the user whose JWT registered it last (user id from the server-side session, never from the request body); logout deletes it, and an FCM deletion that fails offline is retried on the next app start.
- Tokens follow the login lifecycle: register after sign-in and on every signed-in app start, re-register on rotation, delete on logout (explicit and forced-401).
- Ask for notification permission only in context: the notifications screen and a one-time dismissible "Turn on notifications?" card on the signed-in home screen while notifications are off (amended 2026-11-07 — the user delegated the UX open questions: "take best decisions"). The OS prompt fires only from an Allow tap, never at launch. Denial keeps today's in-app-only behaviour.
- A push tap lands exactly where the bell's tap for the same event lands (one shared mapping, same role rules, same attendance guard).
- Job assignment is a notification (user decision, 2026-11-07): creating a job with a technician, or moving a job to a different technician, writes one `job.assigned` row for that technician only — never for the acting admin, never for the previous technician; a failed insert is logged and never fails the job write.
- Foreground pushes show no system notification; they refresh the same stores the Realtime seam refreshes.
- All four RNFB packages pinned to exactly 26.4.1 (v27 is SPM-only; iOS stays on CocoaPods).
- bun only; JDK 17; strict TS; ~300-line files; the backend (and its migration) deploys before any app build that sends tokens ships.

**Never:**
- Data-only pushes, FCM topics, Firebase Auth/Firestore/Remote Config/Storage/Functions.
- `@notifee/react-native` (archived April 2026) or any local-notification library — the Android channel is created natively.
- Firebase/service-account credentials in the app bundle, in git, or inside any repo directory; the project-wide `firebase-adminsdk` key.
- A manual `google_analytics_adid_collection_enabled` meta-data (RNFB injects it from firebase.json; a duplicate breaks the manifest merge).
- Editing MARKETING_VERSION / CURRENT_PROJECT_VERSION lines in project.pbxproj (verify-version-sync needs exactly two of each).
- Migrations applied to the production Supabase project during this change (Fenzit-dev only; prod is a deploy step).
- iOS push delivery (APNs key blocked on Apple enrollment) — iOS code must build cleanly, not deliver.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Register | signed-in start / login | `POST /device-tokens` upserts on token PK, `last_seen_at = now()` | duplicate (StrictMode) is a no-op; 404/network log-only |
| Rotation | `onTokenRefresh` | new token upserted | old one pruned on its next send failure |
| Explicit logout | Log out | FCM `deleteToken` + `DELETE /device-tokens/:token` with the bearer captured first, then session cleared | never blocks or delays logout |
| Forced logout | any 401 | local `deleteToken` only | — |
| Fan-out | new row from an RPC, pg_cron or TS insert; provider `fcm` | claimed (`pushed_at` set) within one sweep; one message per recipient token | not-registered/invalid token → token row deleted; 429/503 → ≤2 retries, backoff + jitter; other → `last_failure` + log |
| Backlog | rows older than `PUSH_MAX_AGE_MINUTES` | never pushed | — |
| Job assigned | admin creates a job for technician T, or reassigns a job to T | one `job.assigned` row for T → bell + push; tap opens T's job detail; T's job list refreshes; with the app open, a 4-second in-app banner from the Realtime path (FCM foreground stays silent) | T is the acting user, or the technician didn't change → no row; insert failure logged, job saved |
| Recipient not current | recipient removed from the row's tenant, disabled, or active in a different tenant | row claimed, nothing sent | logged as skipped |
| Shared phone | user B signs in where user A was | token rebound to B on registration; A's pushes stop reaching it | offline logout: deletion retried on next start |
| Provider | default `noop` | sweep never runs | `fcm` without `GOOGLE_APPLICATION_CREDENTIALS` → boot error |
| Tap | data {type, id}, background/quit | navigates to the bell's target for the role | unknown type → app opens, no navigation |
| Tap before nav ready | cold start | target held, flushed on NavigationContainer `onReady` | dropped when signed out |
| Foreground | `onMessage` | role-aware store refresh only | — |
| Permission | Android 13+ deny / never-ask | in-app only; Allow → OS prompt, never-ask → app Settings | — |

</frozen-after-approval>

## Code Map

fenzit-be (`workspace/core/backend/fenzit-be`):
- `supabase/migrations/20261103000000_account_deletion_requests.sql` -- table + RLS-no-policies template; `20260909000004_notifications_cleanup.sql` -- pg_cron unschedule/schedule template and the pushed_at retention rule
- `src/auth/auth.module.ts:15-63` -- provider registry + boot-error template (SmsDeliveryProvider)
- `src/common/pg/pg-pool.factory.ts` -- pg Pool + `withTransaction`
- `src/reports/engine/` -- in-process poll loop precedent; `report-notifications.ts` -- log-and-drop precedent
- `src/attendance/notification-events.ts` -- attendance/leave event registry (payload fields for push copy)
- `src/notifications/notifications.controller.ts`, `dto/mark-read.dto.ts` -- `@AnyMember` + `@CurrentUser` + DTO style
- `src/app.module.ts` -- Joi env schema, module imports

fenzit-app (`workspace/core/frontend/fenzit-app`):
- `index.js` -- background handler goes before AppRegistry
- `src/App.tsx` -- role branches (mount beside `RealtimeBridge`), 401 handler, login `onComplete`
- `src/features/notifications/useRealtimeNotifications.ts:162-219` -- store-refresh seam to extract
- `src/features/notifications/NotificationsScreen.tsx:187-327` -- bell tap mapping to extract; permission card host
- `src/features/notifications/notificationEventRegistry.ts`, `leaveNotificationModel.ts` -- event classification
- `src/services/attendanceAccessEvents.ts` -- `isAttendanceReachable()` guard
- `src/navigation/navigationRef.ts`, `types.ts` -- navigate outside React; route names
- `src/features/auth/useLogOut.ts` -- logout seam; `src/services/api/apiClient.ts:126-135` -- bearer interceptor (async: clearing the token races queued requests)
- `src/features/onboarding/PermissionsPrimerScreen.tsx` -- add the notifications row (scope D4 lifted)
- `src/features/profile/useMyProfile.ts` -- user id; `src/services/clientMetadata.ts` -- `installedAppVersion()`
- `jest.setup.js`, `jest.config.js` -- native mocks; three suites render App.tsx
- `android/build.gradle`, `android/app/build.gradle`, `app/src/main/AndroidManifest.xml`, `java/com/fenzit/MainApplication.kt`, `res/`
- `ios/Podfile`, `ios/FenzitApp/AppDelegate.swift`, `ios/FenzitApp/Info.plist`, `ios/FenzitApp.xcodeproj/project.pbxproj` (app target `13B07F861A680F5B00A75B9A`, group `13B07FAE1A68108700A75B9A`, Resources `13B07F8E1A680F5B00A75B9A`, target configs `13B07F941A680F5B00A75B9A` / `13B07F951A680F5B00A75B9A`)

## Tasks & Acceptance

**Execution:**
- [ ] `fenzit-be/supabase/migrations/20261107000002_device_tokens.sql` -- `device_tokens` per stack.md (token PK, user_id FK `public.users` ON DELETE CASCADE, platform check android|ios, app_version, created_at, last_seen_at, last_failure), user_id index, RLS on + no policies + revoke anon/authenticated; partial index `notifications(created_at) WHERE pushed_at IS NULL`; daily pg_cron prune of `last_seen_at` older than 90 days -- token store, cheap sweep, hygiene
- [ ] `fenzit-be/src/push/` -- `PushSender` (abstract) with `FcmPushSender` (firebase-admin 14.5.0, `applicationDefault()`, project `fenzit`; HTTP/1.1 transport if the SDK offers it — runtime is Bun) and `NoopPushSender`, registry factory like SMS; `DeviceTokensController` (`POST /device-tokens` upsert → 204, `DELETE /device-tokens/:token` own row → 204, `@AnyMember`) + pg service; `PushSweepService` (interval from OnModuleInit, only when provider is `fcm`, no overlapping ticks; atomic claim `UPDATE … SET pushed_at = now() WHERE id IN (SELECT … FOR UPDATE SKIP LOCKED) RETURNING`, max-age window; one token lookup per batch joined to `users` (not disabled) and `memberships` (status active), sending a row only to tokens whose user is that row's `user_id` with an active membership in that row's `tenant_id`; `sendEach` ≤500; prune/retry/last_failure per matrix); `push-copy.ts` (title/body per event type, wording mirrors the app's cards, humanized fallback) -- CAP-2
- [ ] `fenzit-be/src/app.module.ts`, `.env.example`, `package.json` -- Joi `PUSH_DELIVERY_PROVIDER` noop|fcm (default noop), `GOOGLE_APPLICATION_CREDENTIALS` required when fcm, `PUSH_SWEEP_INTERVAL_SECONDS` (5), `PUSH_MAX_AGE_MINUTES` (15); import PushModule; `bun add firebase-admin@14.5.0` (no lockfile) -- staged rollout; a bad flip is a boot error
- [ ] `fenzit-be/src/jobs/` (job create + update paths; a small `job-notifications.ts` modelled on `reports/engine/report-notifications.ts`) -- after a successful create with a technician, or an update that changes the technician, insert one `job.assigned` row for the new technician (`job_id` set; payload with the job number, customer name and scheduled start when known; no `dedupe_key`); skip when that technician is the acting user; log-and-drop on failure. Plus `job.assigned` copy in `push-copy.ts` ("New job assigned" / job number · customer · time) -- user decision 2026-11-07
- [ ] `fenzit-app` notifications -- `job.assigned` in the technician's inbox renders as a readable job card ("New job assigned", job number) instead of a workflow-step stage; its tap (bell and push) opens TechJobDetail through the shared tap helper; on that event (Realtime or foreground push) the technician's job list refreshes too -- user decision 2026-11-07
- [ ] `fenzit-app/package.json` -- `bun add` the four RNFB packages at exactly 26.4.1
- [ ] `fenzit-app/firebase.json` -- `messaging_android_notification_channel_id: fenzit_default`, `crashlytics_javascript_exception_handler_chaining_enabled: false`, `google_analytics_adid_collection_enabled: false`
- [ ] `fenzit-app/index.js` -- `setBackgroundMessageHandler(getMessaging(), async () => {})` before AppRegistry
- [ ] `src/services/resources/deviceTokens.ts` (+ barrel) -- register/unregister calls; unregister takes an explicit bearer
- [ ] `src/services/telemetry.ts` -- never-throwing wrappers: `logEvent`, `setTelemetryRole(role)` / `clearTelemetryRole()` (Analytics + Crashlytics; role only, no user id) -- one choke point for CAP-4/5
- [ ] `src/features/notifications/useRealtimeNotifications.ts` -- extract the role-aware refresh into exported `refreshStoresForEvent(eventType, role)`; the Realtime path keeps its guards and owner banner, behaviour identical -- the designed push seam (NFR-G)
- [ ] `src/features/notifications/` tap mapping -- extract the bell's kind→route decision (job, report, attendance incl. guard, leave) into a pure helper used by `NotificationsScreen` and push; existing NotificationsScreen tests stay green
- [ ] `src/features/push/` -- `FirebaseBridge` (beside RealtimeBridge): token register + refresh, `onMessage` → `refreshStoresForEvent`, taps (`getInitialNotification` + `onNotificationOpenedApp`) → tap helper via `navigationRef`, pending target flushed by the containers' `onReady`, telemetry user on profile change; a failed logout deletion sets an MMKV flag that the next start (signed in or not) retries before any registration; `notificationPermission.ts` (Android ≥33 `PermissionsAndroid`, iOS RNFB permission, else granted); `unregisterPush({ notifyBackend })` -- CAP-1/3
- [ ] `src/App.tsx` -- mount FirebaseBridge in both branches + `onReady`; 401 handler → `unregisterPush` local-only; `login` event in `onComplete`; `app_open` once per cold start
- [ ] `src/features/auth/useLogOut.ts` -- capture bearer → fire-and-forget unregister → clear telemetry user → existing logout steps
- [ ] `src/features/onboarding/PermissionsPrimerScreen.tsx` -- notifications row with live state + Allow, asked in the Continue sequence, copy per role
- [ ] `src/features/notifications/NotificationsScreen.tsx` -- inline card while notifications are off (Allow / Open settings)
- [ ] analytics call sites -- `job_created` (NewJobScreen success), `job_step_completed` {step} (useWorkflowAdvance success), `notification_tap` {source: push|inbox, type}
- [ ] `jest.setup.js` (+ `transformIgnorePatterns` only if needed) -- mocks for the four RNFB modules
- [ ] `android/build.gradle`, `android/app/build.gradle` -- classpaths google-services 4.5.0 + firebase-crashlytics-gradle 3.0.8; apply google-services, then crashlytics, after the existing plugins
- [ ] `AndroidManifest.xml`, `MainApplication.kt`, `res/` -- AD_ID `tools:node="remove"`; `default_notification_icon` → `@drawable/ic_notification` (white, from the bootsplash F) and `default_notification_color` → brand blue (`tools:replace` if RNFB declares it); channel `fenzit_default` ("Updates", IMPORTANCE_HIGH) created in `onCreate` on API ≥26
- [ ] `ios/Podfile` -- `$RNFirebaseDisableSPM`, `$RNFirebaseAsStaticFramework`, `$RNFirebaseAnalyticsWithoutAdIdSupport` = true at the top; `use_frameworks! :linkage => :static` in the target before `use_react_native!`, replacing the ENV conditional
- [ ] `ios/FenzitApp/AppDelegate.swift` -- `import FirebaseCore`; `FirebaseApp.configure()` after the GMSServices block, before the factory starts
- [ ] `ios/FenzitApp/Info.plist` + new `FenzitApp.entitlements` -- `UIBackgroundModes` [remote-notification]; `aps-environment` development
- [ ] `ios/FenzitApp.xcodeproj/project.pbxproj` -- GoogleService-Info.plist (file ref, build file, group child, Resources), entitlements file ref (group only), `CODE_SIGN_ENTITLEMENTS` in both target configs

**Acceptance Criteria:**
- Given a signed-in Android phone with the app force-closed, when a push with data {type: a job step, id: a job id} is tapped, then the app opens on that job's detail for the role.
- Given the merged manifest, then AD_ID is absent, POST_NOTIFICATIONS is present and the default channel is `fenzit_default`.
- Given a test crash in an installed build, then it appears in Crashlytics tagged 1.2.1.
- Given DebugView, when login, job create, job step and push tap happen, then each catalog event shows up.
- Given `PUSH_DELIVERY_PROVIDER=fcm` without credentials, then fenzit-be refuses to boot; with `noop` it boots and never sweeps.
- Given a fresh Mac, when `bun install` and `bundle exec pod install` run, then pod install logs "SPM disabled" and the workspace builds (checked on the user's machine).

## Implementation Notes

- 2026-11-07: CHECKPOINT 1 approved by the user ("Approve and continue"); service account to be created now. Baseline Android build (pre-change) passed: `:app:assembleMetroDebug` arm64, 3m3s, JDK 17.
- Implementation split across three parallel implementers at the user's request ("start multiple agents"): fenzit-be / fenzit-app JS + Android / fenzit-app `ios/`. The file sets are disjoint; this departs from the workflow's single sequential handoff.
- Tests: per CLAUDE.md test timing, new tests are written after the user confirms the feature works; the step-03 matrix test audit runs then. Until that point, intended tests are named, not written.
- iOS (reviewed by the orchestrator): `CODE_SIGN_ENTITLEMENTS` is set on the **Release** target config only. Xcode refuses to sign a device build carrying `aps-environment` with a free personal team, and the Apple org enrollment is pending — Debug builds therefore stay buildable on any Mac/team (simulator or device), while TestFlight/App Store archives (paid team only) carry Push. iOS push cannot be delivered before enrollment anyway. After enrollment, add the same line to the Debug config to test push on debug device builds.
- FCM sender service account created by the orchestrator: `fenzit-fcm-sender@fenzit.iam.gserviceaccount.com`, sole role Firebase Cloud Messaging API Admin; key at `~/.config/fenzit/fenzit-fcm-sender.json` (600, outside every repo).
- UX pass requested by the user (2026-11-07): the push-facing UI had no design review. Sally (BMAD UX designer) is writing `artifacts/planning-artifacts/ux-designs/ux-fenzit-2026-11-07-push-notifications/EXPERIENCE.md` — wording for every event, lock-screen privacy, Android categories, permission-ask moments, app-open behaviour, the two new cards. After user review, push copy, channels and those UI pieces are revised from it **before** device testing; implementers keep that copy in one place per side meanwhile.
- **Resume point (2026-11-07, mid step-03), for any agent picking this up.** Done: plan approved; service account created; iOS share implemented and reviewed (`ios/` diff in fenzit-app; plutil + `verify:version` pass). In flight when this was written: three background agents — fenzit-be (migration, push module, token endpoints, sweep, `job.assigned`), fenzit-app JS + Android (everything outside `ios/`), and Sally's UX spec. If they were interrupted, files may be partial: compare `git diff` in each repo (baselines in the frontmatter) against the Tasks list; nothing is committed. Next, in order: (1) the user reviews Sally's spec, then apply it to push copy, Android channels, primer row, notifications-off card, job-assigned card and foreground behaviour; (2) step-03 "Stage the Diff" across all three repos; (3) apply the `device_tokens` migration to Fenzit-dev (`yufrzvqpucjrvljmcnls`) only, never production; (4) device tests on the Pixel 6 (`1C301FDF6002ZB`): the Play-installed build must be uninstalled first (signature mismatch) and someone must sign in again with an OTP; run fenzit-be locally on `.env.dev` with `PUSH_DELIVERY_PROVIDER=fcm` and `GOOGLE_APPLICATION_CREDENTIALS` pointing at `~/.config/fenzit/fenzit-fcm-sender.json`; Android builds need JDK 17 (`/usr/local/opt/openjdk@17`); (5) tests only after the user confirms the feature works (CLAUDE.md test timing), then the step-03 matrix audit, step-04 thorough review, step-05. Resume with `/bmad-build` (it lists this in-progress plan) or `/bmad-build artifacts/implementation-artifacts/plan-firebase-integration.md`.
- **UX spec adopted (2026-11-07).** The user delegated Sally's open questions ("take best decisions"); all five recommendations adopted: one-time home-screen card for existing installs (frozen permission bullet amended accordingly), 4-second technician banner for `job.assigned` from the Realtime path only, four Android channels (`fenzit_jobs` Jobs HIGH, `fenzit_attendance` Attendance & leave HIGH, `fenzit_reports` Reports DEFAULT, `fenzit_default` Updates DEFAULT), humanized step keys (no template join), same surfaces on iOS later. Orchestrator adjustments: Jobs channel description made role-neutral; the notifications-off probe checks whether notifications are actually enabled on every Android version. The spec ([EXPERIENCE.md](../planning-artifacts/ux-designs/ux-fenzit-2026-11-07-push-notifications/EXPERIENCE.md)) is now the source of truth for push wording, per-message channel and lock-screen visibility, and those UI pieces; it supersedes the single-channel wording in the Android task above.
- **Review finding fixed in-flight:** the sweep's token lookup unnested one (user, tenant) pair per claimed row, so several rows for one recipient in a tick multiplied every send (3 rows → 9 pushes). Sent back to the backend implementer to make the lookup distinct.
- **RESUME POINT — latest (2026-11-07, supersedes the earlier one).** Done + verified: specs (incl. approved UX spec); service account + key (`~/.config/fenzit/fenzit-fcm-sender.json`); iOS code (reviewed; `CODE_SIGN_ENTITLEMENTS` Release-only); fenzit-be (push module, device tokens, distinct-lookup sweep, `job.assigned`, UX copy/channel/visibility, render.yaml + .dockerignore; typecheck + 1922 tests); `device_tokens` on Fenzit-dev; live sweep test on dev with the real key (claimed 3 / sent 2 / skipped 1 cross-tenant; fake token pruned); fenzit-app JS + Android incl. UX spec (tsc + 305 suites / 3948 tests). Render: secret file `fenzit-fcm-sender.json` saved (prod redeployed the same commit f775182, healthy); the user adds `GOOGLE_APPLICATION_CREDENTIALS=/etc/secrets/fenzit-fcm-sender.json` and `PUSH_DELIVERY_PROVIDER=noop` manually. Orchestrator fix: `android/build.gradle` had a wrong classpath coordinate (`com.google.gms.google-services:google-services`) — now `com.google.gms:google-services:4.5.0`. **The Gradle build with both Firebase plugins enabled has NOT run yet** (the implementer verified with them disabled). Next: (1) `cd android && ./gradlew :app:assembleMetroDebug -PreactNativeArchitectures=arm64-v8a`, then check the merged manifest (no AD_ID; also strip `ACCESS_ADSERVICES_AD_ID`/`ACCESS_ADSERVICES_ATTRIBUTION` for consistency); (2) step-03 "Stage the Diff" for all three repos and read it; (3) temporary test config, reverted before commit: app `API_BASE_URL` → `http://localhost:3000/api/v1` with `adb reverse tcp:3000 tcp:3000`, `SUPABASE_URL`/publishable key → Fenzit-dev; local backend: `nohup python3 /tmp/fenzit-be-local-run.py > /tmp/fenzit-be-local.log 2>&1 &` (clean env from `.env.dev`, SMS mock, fcm); (4) uninstall the Play build on the Pixel 6, install, sign in to dev company "SMOKE Co A" (admin +91 9991784578, employee +91 9991784571) with the OTP printed in the local backend log (`[MOCK SMS] … Code:`), run the Verification device checks; (5) user confirms → write the tests named in the implementer reports → matrix audit → step-04 → step-05; commits only with consent; production cutover per the render.yaml comment. Ops note: the Render service is on the Free plan (sleeps) — reminder pushes created while it sleeps are skipped.
## Plan Change Log

## Review Triage Log

## Design Notes

- **Sweep, not insert hook.** Most rows are written by SECURITY DEFINER RPCs and pg_cron (job steps, leave, attendance); only reports insert from TS. The table header names `pushed_at` "the delivery marker the Phase 2 push worker will set", so one atomic-claim sweep covers every writer, is multi-instance safe, and leaves inserts untouched. Claim-then-send is at-most-once (push is additive). By the original design, claimed rows then fall under the existing 30-day cleanup instead of the 90 days every row effectively gets today.
- **No local-notification library.** notifee is archived; foreground needs no system notification (CAP-3); the only native need, the Android channel, is ~10 lines in MainApplication. RNFB's tap APIs then stay authoritative on both platforms (a notifee-style library takes over the iOS notification-centre delegate).
- **iOS pods.** RNFB 26 defaults to SPM on RN ≥0.75; CocoaPods mode is `$RNFirebaseDisableSPM` + static frameworks (documented combo). Nitro 0.37.1 carries the use_frameworks fix; the reanimated failure is dynamic-only. The committed Podfile.lock is already stale (react-native-maps/Google missing) — the first `pod install` on a Mac regenerates it; commit that lock.
- **iOS signing.** `aps-environment` needs a team that supports Push (the paid org team); a free personal team fails device signing, simulator builds are unaffected. CI's automatic signing adds the capability once enrollment lands.

## Verification

**Commands:**
- `cd workspace/core/backend/fenzit-be && bun run typecheck && bun run test` -- pass
- `cd workspace/core/frontend/fenzit-app && bun run lint && bunx tsc --noEmit && bun run test && bun run verify:version` -- pass
- `cd android && ./gradlew :app:assembleMetroDebug` (JDK 17) -- BUILD SUCCESSFUL; merged manifest has no AD_ID, has POST_NOTIFICATIONS and channel `fenzit_default`
- `plutil -lint ios/FenzitApp/Info.plist ios/FenzitApp/FenzitApp.entitlements ios/FenzitApp.xcodeproj/project.pbxproj` -- OK

**Manual checks (Pixel 6):**
- FCM token logged after login; Firebase-console test message with data {type, id} in background, quit and foreground; tap lands on the bell's target; primer and inbox permission flows; `adb shell setprop debug.firebase.analytics.app com.fenzit` → DebugView events; test crash from an installed build reaches Crashlytics; token endpoints against a local fenzit-be on `.env.dev` (Fenzit-dev database).
