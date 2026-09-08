---
title: 'Frontend — Owner live job-status updates via Supabase Realtime'
type: 'feature'
created: '2026-09-09'
status: 'ready-for-dev'
review_loop_iteration: 0
context: []
baseline_commit: 'efb3d35daf15b429b5e25cb4c3e3bf83e5d573fe'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** When a technician advances a job's workflow, the owner app shows the new status only after the 15s-throttled focus refresh or a pull-to-refresh. Stories 3.1/3.2 (fenzit-be, deploy first) now write a notification and broadcast it to the owner's private Realtime topic `user:<owner_id>:notifications` — nothing in the app listens yet.

**Approach:** Realtime as a **refetch hint, never a source of truth.** Add `@supabase/supabase-js`, a thin singleton client (`src/services/supabaseRealtime.ts`) configured with supabase-js's `accessToken` option (returns the existing bearer JWT from `getAuthToken()` — no Supabase auth, no Supabase session storage), and a `useOwnerNotifications()` hook mounted once in the **owner branch** of `App.tsx`. The hook joins the private channel (foreground-only via `AppState`), and on each event: force-refetches jobs (`loadJobs(..., { force: true })`) and raises a transient banner naming the job and the new step. Unread-badge/list/deep-link is Story 3.4, not this story.

**Latest-tech facts (researched 2026-09-09):**
- supabase-js v2.58; the `createClient(url, publishableKey, { accessToken: async () => token })` option is the supported way to drive Realtime auth with a custom JWT — supabase-js attaches it on channel subscribe automatically. Do **not** use `supabase.auth` (would fight our own auth flow).
- Use the **publishable key** (`sb_publishable_…`) or legacy anon key from the Supabase dashboard — public by design (same class as the API base URL already in the bundle); the `service_role` key never leaves fenzit-be.
- Realtime **Broadcast from Database** is Supabase's recommended pattern (Postgres Changes is explicitly discouraged for new apps). The channel must be created with `config: { private: true }` so server-side RLS authorization on `realtime.messages` applies.
- Bare RN has `WebSocket` natively; supabase-js may need a URL polyfill — if the first connect fails on `URL`/`URLSearchParams`, add `react-native-url-polyfill` and import `'react-native-url-polyfill/auto'` once in `src/services/supabaseRealtime.ts` (verify during Task 0 device run; do not add it speculatively).
- Realtime delivery is at-most-once: the force-refetch-on-event design plus the existing focus-refresh TTL is the correctness net; a missed event self-heals within 15s of the next focus.

## Boundaries & Constraints

**Always:**
- Mount `useOwnerNotifications()` only in the owner branch of `App.tsx`'s role gate (`session?.role === 'technician'` → TechnicianRootNavigator, else owner) — technicians must never open a Realtime socket.
- Gate the subscription on `AppState`: subscribe on `active`, `channel.unsubscribe()` on background, re-subscribe on foreground (one socket while foregrounded, zero while backgrounded — this is the concurrent-subscriber ceiling mitigation).
- Topic/channel name must be derived from the **current session's user id** and rebuilt on login/logout: `user:<userId>:notifications`, matching Story 3.1's broadcast topic format exactly.
- On broadcast event: call `loadJobs(state.scope, state.filter, { force: true })` — the existing store API already force-bypasses the 15s TTL — and surface the banner from the event payload (`job_number`, `step`, `technician_name`).
- Register cleanup with `resetRegistry.registerReset(...)` (tears down channel + client state on the 401 global logout), and subscribe to the auth store so login/logout re-derives the topic.
- Banner auto-dismisses (~4s), renders with design-system tokens only, and taps through to nothing in this story (deep link is 3.4 — keep it non-interactive for now).

**Ask First:**
- **Task 0 device spike:** first run on a real device/simulator — confirm the socket connects with the custom JWT (Story 3.1's backend spike proves the server side; this proves the RN client side, including the URL-polyfill question). If supabase-js's Realtime handshake fails in bare RN for a reason the polyfill doesn't fix, stop and report — do not swap in a hand-rolled WebSocket client without discussion.

**Never:**
- Never put event payloads into app state as job data — the broadcast is a hint; all job state flows from the refetched `GET /jobs` through the existing `useJobs` store (no new source of truth, no sync divergence).
- Never keep the socket alive in background, never subscribe on the technician branch, never use `supabase.auth`/`persistSession` (our JWTs are minted by fenzit-be and stored via the auth store/MMKV — a second session store would drift).
- Never block UI on Realtime: connect failures are silent (log-only) — the app is fully functional without the socket (it's an optimization layer over focus-refresh).
- Do not implement the bell icon, badge, notifications list, or mark-read (Story 3.4's scope; Story 3.2's endpoints are not called here).
- No new deps beyond `@supabase/supabase-js` (and `react-native-url-polyfill` only if the Task 0 spike proves it needed).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Event while foregrounded | Technician advances a step | Jobs list refetches (forced) within the same tick; banner shows "{technician_name} · {job_number} · {step}" | N/A |
| App backgrounded | Socket torn down | Zero subscriptions; no battery/socket cost; events missed (accepted) | N/A |
| App returns to foreground | Resubscribe | Socket re-established; existing 15s focus-refresh TTL covers the gap on next focus — no forced refetch on resubscribe itself | N/A |
| Socket drop / reconnect | Network blip mid-session | supabase-js auto-reconnects; hook re-syncs channel status; first focus refetch covers dropped events | Logged, silent to user |
| Logout / 401 reset | `runAllResets()` | Channel unsubscribed, topic state cleared; no socket as logged-out user | N/A |
| Login as different user | Session changes | Topic rebuilt from new `sub` — never listens to the previous user's topic | N/A |
| Technician session | Hook mounted? | No — owner branch only; zero Realtime code runs | N/A |
| Supabase outage | Socket never connects | App unchanged from today's behavior (focus-refresh/pull-to-refresh); silent log | Logged, silent |
| Payload shape drift | BE sends unexpected payload | Banner falls back to generic copy ("Job status updated"); refetch still happens | Logged, silent |

</frozen-after-approval>

## Code Map

- `package.json` -- UPDATE: `bun add @supabase/supabase-js` (v2.58.x)
- `src/config/index.ts` -- UPDATE: add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` constants next to `API_BASE_URL` (same comment style; values from the Supabase dashboard — publishable key, **not** service_role)
- `src/services/supabaseRealtime.ts` -- NEW (~60 lines): singleton `createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, { accessToken: async () => getAuthToken(), auth: { persistSession: false, autoRefreshToken: false } })` + `getOwnerChannel(userId)` helper joining `user:<userId>:notifications` with `config: { private: true }` + conditional url-polyfill import; the hook only subscribes when `getAuthToken()` returns a token — a null token (logged-out window) means no subscription attempt is made re-export from `src/services/index.ts` (the barrel re-exports every service — `authToken` is re-exported at `src/services/index.ts:23`)
- `src/features/notifications/useOwnerNotifications.ts` -- NEW (~120 lines): the hook — AppState gating, topic derivation from the auth-store session, `on('broadcast', { event: 'INSERT' })` handler (the event name is `'INSERT'` — Story 3.1's trigger passes `TG_OP` as both `event_name` and `operation`, and the trigger is AFTER INSERT only) calling `loadJobs(..., { force: true })` + banner state, resetRegistry + auth-store cleanup. **Wire shape:** the event delivers the raw `notifications` row, snake_case — top-level `id`/`job_id`/`event_type`/`read_at`/`created_at`, with `job_number`/`step`/`technician_name` nested inside `payload`; the banner handler reads `payload.job_number` etc., never top-level fields. The handler also ignores events whose topic ≠ the current session's topic (an in-flight event can land after a user switch before teardown completes). A burst of N events collapses via `loadJobs`'s shared `inFlight` de-dup — no extra throttling needed. Keep under the ~300-line file limit; extract `notificationBannerModel.ts` (pure banner text/state logic, unit-testable) if it grows
- `src/App.tsx:57-71` -- UPDATE (mount mechanics matter — verified 2026-09-09): the role gate is a **conditional render chain, not an early return** (`session?.role === 'technician'` at line 57 → `TechnicianRootNavigator`; `else` at line 65 → `RootNavigator`; `content` is rendered at line 77). Hooks cannot be called conditionally at `App()` top level — so the hook must be mounted via a small **bridge component** (e.g. `OwnerRealtimeBridge`, renders the `StatusBanner` and returns null otherwise) placed inside the owner `else` branch next to `<RootNavigator />`. Never mount it at `App()` top level (technicians would open a socket) and never inside `RootNavigator` unconditionally without the role check. Note `App.tsx:32-38` already wires `setOnUnauthorized` → `runAllResets()` — the resetRegistry teardown composes with it automatically
- `src/components/` (app-specific) -- NEW: `StatusBanner.tsx` (transient top banner, design-system tokens, auto-dismiss) — extend tokens/components, never hard-code
- `src/features/jobs/useJobs.ts:126,281` -- REFERENCE (no change): `loadJobs(scope, filter, opts: { force?: boolean })` (lines 126-130) and `refresh` (line 281) are the existing forced-refetch APIs. The 15s TTL is a **hardcoded literal `15_000` at line 137** — the `FOCUS_REFRESH_TTL_MS` constant in `src/constants/index.ts:14` exists but `useJobs` does not import it, so don't assume constant/behavior are linked
- `src/services/authToken.ts:20` -- REFERENCE (no change): `getAuthToken()` (line 20), `setAuthToken` (31), `clearAuthToken` (40), MMKV-backed — `getAuthToken()` is the single token source (same one apiClient uses)
- `src/services/resetRegistry.ts:44` -- REFERENCE (no change): `registerReset(fn: () => void): () => void` (returns an unregister fn); `runAllResets()` at line 62 bumps the epoch and try/catches each reset. Existing registrants to mirror: `useJobs.ts:264`, `useCustomers.ts:209`, `useTechnicians.ts:64`, `useTechnicianJobs.ts:322`, `useMyProfile.ts:195`, `useSkills.ts:234`

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (device spike): connect on device/simulator with the custom JWT, confirm `SUBSCRIBED` on a private channel and a test broadcast received; resolve the url-polyfill question; record results in the story before building the hook
- [ ] Deps + config: `@supabase/supabase-js`, `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` in `src/config/index.ts`
- [ ] `src/services/supabaseRealtime.ts` singleton + channel helper
- [ ] `src/features/notifications/useOwnerNotifications.ts` (+ extracted model file if needed) with AppState gating, force-refetch, resetRegistry/auth-store wiring
- [ ] `StatusBanner` component + mount in the owner branch of `App.tsx`
- [ ] Unit tests: banner model (payload → text, drift fallback), topic derivation, AppState gate logic, resetRegistry teardown, and the technician-safety AC automated: the `OwnerRealtimeBridge` probe-rendered with a mocked technician session renders nothing (no banner, no subscription) — all with the supabase client mocked (no real socket in jest)

**Acceptance Criteria:**
- Given the owner app foregrounded, when a technician advances a step, then the jobs list reflects the new status immediately (forced refetch) and a banner names the technician, job number, and step
- Given the app backgrounded, then there are zero open Realtime subscriptions; on foreground the subscription re-establishes
- Given logout, session expiry (401 reset), or a login as another user, then the channel is torn down and rebuilt from the new session — never listening on a stale topic
- Given no connectivity to Supabase Realtime, then the app behaves exactly as today (focus-refresh/pull-to-refresh), with failures logged and silent
- Given a technician session, then no Realtime code executes at all

## Design Notes

- **Why hint-not-truth:** Realtime is at-most-once and the app's whole state model is already "REST is truth, refetch to update". Making the event itself a refetch trigger means zero new state to reconcile, and every existing correctness property (idempotency keys, 15s TTL, pull-to-refresh) keeps working unchanged.
- **Why foreground-only:** Supabase Realtime's practical ceiling (~1,000 concurrent subscribers per project on standard compute) is the Phase 1 scaling limit identified in the architecture discussion; background sockets would multiply it for no benefit (no push exists yet). Phase 2 (push via FCM/APNs) is the planned answer for closed-app delivery. iOS nuance: subscribe **only** on `'active'` — `'inactive'` (app switcher, notification centre glance) counts as background and tears down; the brief teardown/re-subscribe flap when the user glances at the notification centre is accepted battery-friendly behaviour, not a bug.
- **Banner event-collision rules:** a new broadcast while a banner is visible **replaces** the content and **resets** the ~4s timer (the first event's timer must never dismiss the second event's banner); each event also re-issues the force-refetch, which `loadJobs`'s shared `inFlight` de-dup collapses if one is already running.
- **Why `auth.persistSession: false`:** supabase-js's auth module is for Supabase Auth sessions; fenzit-be mints and owns our JWT lifecycle. The `accessToken` callback alone is the entire integration surface — anything more invites session-store drift.
- **Swappable seam for Phase 2:** all socket logic lives behind the hook + `supabaseRealtime.ts` — when Phase 2 introduces push notifications or a self-hosted gateway, the refetch/banner behavior is re-triggerable from a different event source without touching the stores or screens. Concretely: structure the hook around a single exported **`handleJobStatusEvent(payload)`** (pure: force-refetch + banner state) that the Realtime subscription calls — the Phase 2 FCM data-message handler will call the *same function* from its foreground/background-message listener, so push integration is a new caller, not a rewrite.
- **Previous-work intelligence (from Epic 1/2 dev records + code re-verified 2026-09-09):**
  - **Tests run via `bun run test`** (the jest script) — bare `bun test` fails on RN Flow types. `jest.config.js` already sets `watchman: false`, so no extra flag is needed. Tests use **`react-test-renderer` probe components** (`@testing-library/react-native` is NOT installed) and mock the services barrel — e.g. `__tests__/useJobs.test.ts` does `jest.mock('../src/services', () => ({ jobService: {...} }))` then mounts a probe via `ReactTestRenderer`. Mock the supabase client module the same way — never open a real socket in jest.
  - **AppState has zero precedent in the app** (no file uses it today) — the foreground gate is genuinely new code; keep it pure/testable (a small `shouldSubscribe(state: string): boolean` helper) so it doesn't need a device to unit-test.
  - **Config style:** `src/config/index.ts` is deliberately plain constants (no env-file library); its doc comment names `react-native-config` as the sanctioned future swap. Metro inlines `process.env.X` at bundle time (the `DEV_API_HOST=<ip> bun run android:standalone` precedent) — if the publishable key ever needs per-build overrides, use that mechanism, not a new config library. `API_BASE_URL` currently ends in `/api/v1` and a temp `DEV_API_HOST` LAN-IP hardcode exists (2026-09-05) — add the two SUPABASE_* constants as sibling block-commented exports, nothing more.
  - **Auth token single source:** `getAuthToken()`/`clearAuthToken()` in `src/services/authToken.ts` (barrel-exported from `src/services/index.ts:23`) is what apiClient uses; the `accessToken` callback must read the same source — a second token store would drift from the 401 reset flow.
  - **resetRegistry convention:** every module-level teardown registers via `registerReset(...)` from its own file (the one-line-per-store pattern documented in `resetRegistry.ts`) — the realtime teardown follows it the same way `useJobs`/apiClient do.
  - **401 semantics:** only a 401 on a request that actually carried a token triggers the global reset (apiClient's `hadToken` guard) — realtime teardown hooks into the reset registry, not into axios interceptors.
  - **Icon-only touch targets:** any icon button uses the theme's `touch.min` token (explicit `minWidth`/`minHeight` + `hitSlop={8}`) — the ≥44px convention consolidated during the 2026-09-09 batch review. `IconButton` (`src/components/ui/IconButton.tsx`) ships sizes sm 36 / md 44 / lg 52 and *requires* a `label`.
  - **Absolute imports** (`@components`, `@services`, `@theme`, …) are mandatory in all new files (fenzo-app CLAUDE.md; tsconfig `paths` already map them — note some legacy files use relative imports; do not copy that).
  - **Versions (verified 2026-09-09):** react-native 0.86.0, react 19.2.3, `lucide-react-native` ^1.21.0 (the only icon set; needs `react-native-svg`, already present), `react-native-mmkv` ^4.3.2. `@supabase/supabase-js` and `react-native-url-polyfill` are NOT installed — `bun add` them fresh (supabase-js latest v2.x at implementation time).
- Cross-repo ordering: Stories 3.1/3.2 (fenzit-be, additive) merge/deploy **first**; this story (fenzo-app) consumes the broadcast topic. The FE alone against a not-yet-deployed BE simply never receives events (graceful).

## Verification

**Commands:**
- `bun run test` -- expected: new banner/topic/gating tests pass (use `bun run test`, never bare `bun test`)
- `bun run lint` -- expected: clean on new files
- Manual (Task 0 device run): owner app open on Jobs tab → technician advances a step from the technician app → list updates + banner appears without pull-to-refresh; background the owner app → advance again → refetch happens on next foreground/focus

## Suggested Review Order

1. `src/services/supabaseRealtime.ts` — client options (`persistSession: false`, `accessToken`), publishable key from config, channel `private: true`.
2. `useOwnerNotifications.ts` — AppState gate, topic-from-session, event → force-refetch, resetRegistry + auth-store teardown.
3. `App.tsx` — bridge component mounted **only** in the owner `else` branch (not at top level, not in the technician branch).
4. `StatusBanner` — design-system tokens, auto-dismiss.
5. Config diff — no secret material (`service_role` must not appear anywhere in `src/`).
6. Unit tests.