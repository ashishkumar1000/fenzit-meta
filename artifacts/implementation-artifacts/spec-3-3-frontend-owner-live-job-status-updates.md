---
title: 'Frontend — Owner live job-status updates via Supabase Realtime'
type: 'feature'
created: '2026-09-09'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: 'efb3d35daf15b429b5e25cb4c3e3bf83e5d573fe'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">
<!-- Renegotiated 2026-09-09 (human-approved during bmad-code-review of the BE endpoint):
     the original design passed the login JWT to Realtime directly; live testing
     (Story 3.1 spike) proved Realtime rejects it (no exp, role not a Postgres
     role), so fenzit-be gained GET /auth/realtime-token (owner-only, 1h exp,
     role 'authenticated') and the client exchanges for that short-lived token.
     The sections below describe the renegotiated design. -->

## Intent

**Problem:** When a technician advances a job's workflow, the owner app shows the new status only after the 15s-throttled focus refresh or a pull-to-refresh. Stories 3.1/3.2 (fenzit-be, deploy first) now write a notification and broadcast it to the owner's private Realtime topic `user:<owner_id>:notifications` — nothing in the app listens yet.

**Approach:** Realtime as a **refetch hint, never a source of truth.** Add `@supabase/supabase-js`, a thin singleton client (`src/services/supabaseRealtime.ts`) configured with supabase-js's `accessToken` option — the callback returns a **short-lived exchanged token** from the fenzit-be endpoint `GET /auth/realtime-token` (owner-only, 1 h `exp`, `role: 'authenticated'`; Realtime rejects the login JWT — no `exp`, role not a Postgres role — per Story 3.1's live spike), cached in-memory by `realtimeToken.ts` and refreshed near expiry — no Supabase auth, no Supabase session storage — and a `useOwnerNotifications()` hook mounted once in the **owner branch** of `App.tsx`. The hook joins the private channel (foreground-only via `AppState`), and on each event: force-refetches jobs (`loadJobs(..., { force: true })`) and raises a transient banner naming the job and the new step. Unread-badge/list/deep-link is Story 3.4, not this story.

**Latest-tech facts (researched 2026-09-09):**
- supabase-js v2.58; the `createClient(url, publishableKey, { accessToken: async () => token })` option is the supported way to drive Realtime auth with a custom JWT — supabase-js attaches it on channel subscribe automatically. The token is the **exchanged** one from `GET /auth/realtime-token`, not the login JWT. Do **not** use `supabase.auth` (would fight our own auth flow).
- Use the **publishable key** (`sb_publishable_…`) or legacy anon key from the Supabase dashboard — public by design (same class as the API base URL already in the bundle); the `service_role` key never leaves fenzit-be.
- Realtime **Broadcast from Database** is Supabase's recommended pattern (Postgres Changes is explicitly discouraged for new apps). The channel must be created with `config: { private: true }` so server-side RLS authorization on `realtime.messages` applies.
- Bare RN has `WebSocket` natively; supabase-js may need a URL polyfill — if the first connect fails on `URL`/`URLSearchParams`, add `react-native-url-polyfill` and import `'react-native-url-polyfill/auto'` once in `src/services/supabaseRealtime.ts` (verify during Task 0 device run; do not add it speculatively).
- Realtime delivery is at-most-once: the force-refetch-on-event design plus the existing focus-refresh TTL is the correctness net; a missed event self-heals within 15s of the next focus.

## Boundaries & Constraints

**Always:**
- Mount `useOwnerNotifications()` only in the owner branch of `App.tsx`'s role gate (`session?.role === 'technician'` → TechnicianRootNavigator, else owner) — technicians must never open a Realtime socket.
- Gate the subscription on `AppState`: subscribe on `active`, `channel.unsubscribe()` on background, re-subscribe on foreground (one socket while foregrounded, zero while backgrounded — this is the concurrent-subscriber ceiling mitigation).
- Topic/channel name must be derived from the **current session's user id** and rebuilt on login/logout: `user:<userId>:notifications`, matching Story 3.1's broadcast topic format exactly. **Renegotiated with human approval (2026-09-09 code review):** the user id comes from the **profile store** (`useMyProfile` → `profile.id`), not the auth store — `useAuth`'s `Session` is `{ role, tenantId }` and carries no user id, so the originally prescribed source cannot supply it. The profile store resets to null on the global 401 reset, so login/logout re-derivation is preserved. Accepted consequence: socket startup waits for `GET /users/me` to load — a profile-fetch failure is silent degradation under the same contract.
- On broadcast event: call `loadJobs(state.scope, state.filter, { force: true })` — the existing store API already force-bypasses the 15s TTL — and surface the banner from the event payload (`job_number`, `step`, `technician_name`). **Extended with human approval (2026-09-09 device spike):** the event ALSO force-refetches the profile store (`loadMyProfile({ force: true })`) — Home renders from `GET /users/me` (job counts + Today's-jobs), a different store from the Jobs tab's, so the whole dashboard updates live. `/users/me` is the heavy endpoint; one event per technician step is acceptable (a lightweight summary endpoint is the recorded future optimization).
- Register cleanup with `resetRegistry.registerReset(...)` (tears down channel + client state on the 401 global logout); the profile store resetting to null on that same reset is what re-derives the topic on the next login (see the topic bullet above).
- Banner auto-dismisses (~4s), renders with design-system tokens only, and taps through to nothing in this story (deep link is 3.4 — keep it non-interactive for now); the overlay is `pointerEvents: 'box-none'` so it never swallows touches on the UI beneath it.

**Ask First:**
- **Task 0 device spike:** first run on a real device/simulator — confirm the socket connects with the **exchanged** realtime token from `GET /auth/realtime-token` (Story 3.1's backend spike proved Realtime accepts this claim set server-side; this proves the RN client side, including the URL-polyfill question). If supabase-js's Realtime handshake fails in bare RN for a reason the polyfill doesn't fix, stop and report — do not swap in a hand-rolled WebSocket client without discussion.

**Never:**
- Never put event payloads into app state as job data — the broadcast is a hint; all job state flows from the refetched `GET /jobs` through the existing `useJobs` store (no new source of truth, no sync divergence).
- Never keep the socket alive in background, never subscribe on the technician branch, never use `supabase.auth`/`persistSession` (our JWTs are minted by fenzit-be and stored via the auth store/MMKV — a second session store would drift).
- Never block UI on Realtime: connect failures are silent (log-only) — the app is fully functional without the socket (it's an optimization layer over focus-refresh).
- Do not implement the bell icon, badge, notifications list, or mark-read (Story 3.4's scope; Story 3.2's endpoints are not called here).
- No new deps beyond `@supabase/supabase-js` (and `react-native-url-polyfill` only if the Task 0 spike proves it needed). **Renegotiated with human approval (2026-09-09 code review):** `text-encoding-polyfill` added — the Task 0 spike proved "Broadcast from Database" delivers BINARY frames and Hermes ships no `TextDecoder`, so every incoming broadcast crashed without it.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Event while foregrounded | Technician advances a step | Jobs list refetches (forced) within the same tick; Home's counts refresh via the profile-store force-refetch; banner shows "{technician_name} · {job_number} · {step}" | N/A |
| App backgrounded | Socket torn down | Zero subscriptions; no battery/socket cost; events missed (accepted) | N/A |
| App returns to foreground | Resubscribe | Socket re-established; existing 15s focus-refresh TTL covers the gap on next focus — no forced refetch on resubscribe itself | N/A |
| Socket drop / reconnect | Network blip mid-session | supabase-js auto-reconnects; hook re-syncs channel status; first focus refetch covers dropped events | Logged, silent to user |
| Logout / 401 reset | `runAllResets()` | Channel unsubscribed, topic state cleared; no socket as logged-out user | N/A |
| Login as different user | Session changes | Topic rebuilt from new `sub` — never listens to the previous user's topic | N/A |
| Technician session | Hook mounted? | No — owner branch only; zero Realtime code runs | N/A |
| Supabase outage | Socket never connects | App unchanged from today's behavior (focus-refresh/pull-to-refresh); silent log | Logged, silent |
| Payload shape drift | BE sends unexpected payload | Banner falls back to generic copy ("Job status updated"); refetch still happens | Logged, silent |
| Realtime token expired / near expiry | `expiresAt` − 60 s reached (foreground) or next (re)connect | `getRealtimeToken()` refetches `GET /auth/realtime-token` before use (in-memory cache, 60 s margin); no socket drop handling needed by the hook | Failed exchange → no subscription attempt; app falls back to focus refresh (silent) |

</frozen-after-approval>

## Code Map

- `package.json` -- UPDATE: `bun add @supabase/supabase-js` (v2.58.x)
- `src/config/index.ts` -- UPDATE: add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` constants next to `API_BASE_URL` (same comment style; values from the Supabase dashboard — publishable key, **not** service_role)
- `src/services/supabaseRealtime.ts` -- NEW (~60 lines): singleton `createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, { accessToken: async () => getRealtimeToken(), auth: { persistSession: false, autoRefreshToken: false } })` — the callback resolves the **exchanged** short-lived token via `realtimeToken.ts` (which calls `GET /auth/realtime-token`, caches it in-memory, and refreshes 60 s before `expiresAt`); plus `getOwnerChannel(userId)` helper joining `user:<userId>:notifications` with `config: { private: true }` + conditional url-polyfill import; the hook only subscribes when `getRealtimeToken()` resolves a token — a failed exchange (null, logged-out window or BE down) means no subscription attempt is made; re-export from `src/services/index.ts` (the barrel re-exports every service — `realtimeToken` is re-exported alongside `authToken` at `src/services/index.ts:23`)
- `src/features/notifications/useOwnerNotifications.ts` -- NEW (~120 lines): the hook — AppState gating, topic derivation from the profile store's user id (2026-09-09 review renegotiation — see the Boundaries topic bullet; the auth-store Session carries no user id), `on('broadcast', { event: 'INSERT' })` handler (the event name is `'INSERT'` — Story 3.1's trigger passes `TG_OP` as both `event_name` and `operation`, and the trigger is AFTER INSERT only) calling `loadJobs(..., { force: true })` + `loadMyProfile({ force: true })` (user-approved extension) + banner state, resetRegistry cleanup. **Wire shape:** the event delivers the raw `notifications` row, snake_case — top-level `id`/`job_id`/`event_type`/`read_at`/`created_at`, with `job_number`/`step`/`technician_name` nested inside `payload`; the banner handler reads `payload.job_number` etc., never top-level fields. The handler also ignores events whose topic ≠ the current session's topic (an in-flight event can land after a user switch before teardown completes). A burst of N events collapses via `loadJobs`'s shared `inFlight` de-dup — no extra throttling needed. Keep under the ~300-line file limit; extract `notificationBannerModel.ts` (pure banner text/state logic, unit-testable) if it grows
- `src/App.tsx:57-71` -- UPDATE (mount mechanics matter — verified 2026-09-09): the role gate is a **conditional render chain, not an early return** (`session?.role === 'technician'` at line 57 → `TechnicianRootNavigator`; `else` at line 65 → `RootNavigator`; `content` is rendered at line 77). Hooks cannot be called conditionally at `App()` top level — so the hook must be mounted via a small **bridge component** (e.g. `OwnerRealtimeBridge`, renders the `StatusBanner` and returns null otherwise) placed inside the owner `else` branch next to `<RootNavigator />`. Never mount it at `App()` top level (technicians would open a socket) and never inside `RootNavigator` unconditionally without the role check. Note `App.tsx:32-38` already wires `setOnUnauthorized` → `runAllResets()` — the resetRegistry teardown composes with it automatically
- `src/components/` (app-specific) -- NEW: `StatusBanner.tsx` (transient top banner, design-system tokens, auto-dismiss) — extend tokens/components, never hard-code
- `src/features/jobs/useJobs.ts:126,281` -- REFERENCE (no change): `loadJobs(scope, filter, opts: { force?: boolean })` (lines 126-130) and `refresh` (line 281) are the existing forced-refetch APIs. The 15s TTL is a **hardcoded literal `15_000` at line 137** — the `FOCUS_REFRESH_TTL_MS` constant in `src/constants/index.ts:14` exists but `useJobs` does not import it, so don't assume constant/behavior are linked
- `src/services/authToken.ts:20` -- REFERENCE (no change): `getAuthToken()` (line 20), `setAuthToken` (31), `clearAuthToken` (40), MMKV-backed — the login JWT apiClient uses; the **Realtime token is a separate short-lived token** from `GET /auth/realtime-token`, cached only in-memory by `realtimeToken.ts` (never persisted to MMKV) so it cannot drift from the 401 reset flow
- `src/services/resetRegistry.ts:44` -- REFERENCE (no change): `registerReset(fn: () => void): () => void` (returns an unregister fn); `runAllResets()` at line 62 bumps the epoch and try/catches each reset. Existing registrants to mirror: `useJobs.ts:264`, `useCustomers.ts:209`, `useTechnicians.ts:64`, `useTechnicianJobs.ts:322`, `useMyProfile.ts:195`, `useSkills.ts:234`

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (device spike): connect on device/simulator with the exchanged realtime token from `GET /auth/realtime-token`, confirm `SUBSCRIBED` on a private channel and a test broadcast received; resolve the url-polyfill question; record results in the story before building the hook
- [x] Deps + config: `@supabase/supabase-js`, `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` in `src/config/index.ts`
- [x] `src/services/supabaseRealtime.ts` singleton + channel helper
- [x] `src/features/notifications/useOwnerNotifications.ts` (+ extracted model file if needed) with AppState gating, force-refetch, resetRegistry/auth-store wiring
- [x] `StatusBanner` component + mount in the owner branch of `App.tsx`
- [x] Unit tests: banner model (payload → text, drift fallback), topic derivation, AppState gate logic, resetRegistry teardown, and the technician-safety AC automated: the `OwnerRealtimeBridge` probe-rendered with a mocked technician session renders nothing (no banner, no subscription) — all with the supabase client mocked (no real socket in jest)

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
- **Why `auth.persistSession: false`:** supabase-js's auth module is for Supabase Auth sessions; fenzit-be mints and owns our JWT lifecycle. The `accessToken` callback returning the exchanged short-lived token is the entire integration surface — anything more invites session-store drift.
- **Swappable seam for Phase 2:** all socket logic lives behind the hook + `supabaseRealtime.ts` — when Phase 2 introduces push notifications or a self-hosted gateway, the refetch/banner behavior is re-triggerable from a different event source without touching the stores or screens. Concretely: structure the hook around a single exported **`handleJobStatusEvent(payload)`** (pure: force-refetch + banner state) that the Realtime subscription calls — the Phase 2 FCM data-message handler will call the *same function* from its foreground/background-message listener, so push integration is a new caller, not a rewrite.
- **Previous-work intelligence (from Epic 1/2 dev records + code re-verified 2026-09-09):**
  - **Tests run via `bun run test`** (the jest script) — bare `bun test` fails on RN Flow types. `jest.config.js` already sets `watchman: false`, so no extra flag is needed. Tests use **`react-test-renderer` probe components** (`@testing-library/react-native` is NOT installed) and mock the services barrel — e.g. `__tests__/useJobs.test.ts` does `jest.mock('../src/services', () => ({ jobService: {...} }))` then mounts a probe via `ReactTestRenderer`. Mock the supabase client module the same way — never open a real socket in jest.
  - **AppState has zero precedent in the app** (no file uses it today) — the foreground gate is genuinely new code; keep it pure/testable (a small `shouldSubscribe(state: string): boolean` helper) so it doesn't need a device to unit-test.
  - **Config style:** `src/config/index.ts` is deliberately plain constants (no env-file library); its doc comment names `react-native-config` as the sanctioned future swap. Metro inlines `process.env.X` at bundle time (the `DEV_API_HOST=<ip> bun run android:standalone` precedent) — if the publishable key ever needs per-build overrides, use that mechanism, not a new config library. `API_BASE_URL` currently ends in `/api/v1` and a temp `DEV_API_HOST` LAN-IP hardcode exists (2026-09-05) — add the two SUPABASE_* constants as sibling block-commented exports, nothing more.
  - **Auth token single source:** `getAuthToken()`/`clearAuthToken()` in `src/services/authToken.ts` (barrel-exported from `src/services/index.ts:23`) is what apiClient uses. The Realtime token is deliberately a **second, in-memory-only** store (`realtimeToken.ts`): it is derived from the login JWT via `GET /auth/realtime-token`, never persisted, and registers `clearRealtimeToken` with `registerReset` so the 401 reset clears both stores together — that is what keeps the two from drifting.
  - **resetRegistry convention:** every module-level teardown registers via `registerReset(...)` from its own file (the one-line-per-store pattern documented in `resetRegistry.ts`) — the realtime teardown follows it the same way `useJobs`/apiClient do.
  - **401 semantics:** only a 401 on a request that actually carried a token triggers the global reset (apiClient's `hadToken` guard) — realtime teardown hooks into the reset registry, not into axios interceptors.
  - **Icon-only touch targets:** any icon button uses the theme's `touch.min` token (explicit `minWidth`/`minHeight` + `hitSlop={8}`) — the ≥44px convention consolidated during the 2026-09-09 batch review. `IconButton` (`src/components/ui/IconButton.tsx`) ships sizes sm 36 / md 44 / lg 52 and *requires* a `label`.
  - **Absolute imports** (`@components`, `@services`, `@theme`, …) are nominally mandatory in all new files (fenzo-app CLAUDE.md; tsconfig `paths` already map them). **Decision (2026-09-09 code review):** keep **relative imports** like the new Story 3.3 files — zero of 229 source files use a project alias and jest has no `moduleNameMapper`, so the CLAUDE.md mandate has never been applied; converting new files alone would make them the only alias users. The CLAUDE.md section is amended to match reality; revisit if the codebase ever adopts aliases wholesale.
  - **Versions (verified 2026-09-09):** react-native 0.86.0, react 19.2.3, `lucide-react-native` ^1.21.0 (the only icon set; needs `react-native-svg`, already present), `react-native-mmkv` ^4.3.2. `@supabase/supabase-js` and `react-native-url-polyfill` are NOT installed — `bun add` them fresh (supabase-js latest v2.x at implementation time).
- Cross-repo ordering: Stories 3.1/3.2 (fenzit-be, additive) merge/deploy **first**; this story (fenzo-app) consumes the broadcast topic. The FE alone against a not-yet-deployed BE simply never receives events (graceful).

## Verification

**Commands:**
- `bun run test` -- expected: new banner/topic/gating tests pass (use `bun run test`, never bare `bun test`)
- `bun run lint` -- expected: clean on new files
- Manual (Task 0 device run): owner app open on Jobs tab → technician advances a step from the technician app → list updates + banner appears without pull-to-refresh; background the owner app → advance again → refetch happens on next foreground/focus

### Review Findings

<!-- bmad-code-review 2026-09-09 — fenzit-be GET /auth/realtime-token (BE support, additive). 4 layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor (full mode). -->

- [x] [Review][Decision] Minted Realtime tokens are valid app-wide JWTs, and the mint endpoint accepts them — `JwtAuthGuard` builds a `RequestUser` from any token signed with `SUPABASE_JWT_SECRET` without checking the role (`src/common/guards/jwt-auth.guard.ts:56-66`), so a minted `role: 'authenticated'` token is accepted by every endpoint without `@Roles` (including the deliberately-not-role-gated `/notifications` endpoints) and can call `GET /auth/realtime-token` itself to renew indefinitely — the 1 h TTL only caps a leaked copy if the copy is not kept alive. `JwtPayload.role` is typed as the `Role` enum, so the type-level assumption also breaks silently. [blind-hunter+edge-case-hunter] **RESOLVED (both options applied):** `@Roles(Role.OWNER)` on the mint route AND `JwtAuthGuard` now rejects any token whose role claim is not `owner`/`technician` (outside the verify catch so its message survives); new guard tests (realtime token rejected with its own message, roleless token rejected) + controller test asserting owner-only metadata. Realtime tokens are now socket-only and cannot self-renew.
- [x] [Review][Decision] Frozen spec section is stale — it still prescribes `accessToken: () => getAuthToken()` (login JWT) as "the entire integration surface", but the BE endpoint is its unplanned replacement; Task 0's purpose silently changed to validating the *exchanged* token, and the I/O matrix has no token-expiry row. The frozen section must be renegotiated/updated, not just the code. [acceptance-auditor] **RESOLVED (update chosen):** frozen section renegotiated with human approval 2026-09-09 — Approach/latest-tech/Task 0/Code Map/Design Notes now describe the exchanged token, and a token-expiry row was added to the I/O matrix.
- [x] [Review][Decision] Endpoint serves technicians — the story only needs owner access; technician minting is unrequested scope (not a security hole: RLS keys on `sub`, so a technician token only reaches their own topic). Restrict to `Role.OWNER` or record the allowance as intentional. [acceptance-auditor] **RESOLVED (restrict chosen):** route is `@Roles(Role.OWNER)`; docs note Story 3.4 may widen it later.
- [x] [Review][Patch] No test executes the route — unit tests mock the signer, so route wiring, guard population, 401-without-JWT, response shape, and real-signer claim/`exp` behaviour are all unverified [src/auth/auth.controller.ts:151] [verification-gap+blind-hunter] **RESOLVED:** new `src/auth/auth.controller.spec.ts` — delegation test + owner-only metadata assertion (guard population itself now covered by the expanded jwt-auth.guard.spec.ts).
- [x] [Review][Patch] `jsonwebtoken` throws if both `expiresIn` and an explicit `exp` exist — `signOptions` is currently `{}` (interim, until refresh tokens land); add a guard comment so the future refresh-token change doesn't turn this endpoint into 500s [src/auth/auth.service.ts:213] [verification-gap] **RESOLVED:** comment on the signAsync call + spec assertion that no options object is passed.
- [x] [Review][Patch] Doc contradiction: header says login JWTs "last 7 days" while the new section says "never expires" (app.module comment confirms never-expire) [docs/api-contracts.md:5] [blind-hunter] **RESOLVED:** header now states never-expire (interim until refresh tokens) and mentions the guard's role filter.
- [x] [Review][Patch] Doc: Notifications section (where a client needs the socket token) never cross-references the new endpoint, and the Realtime-claims explanation is duplicated between the Jobs side-effect paragraph and the new Auth section [docs/api-contracts.md:340] [blind-hunter] **RESOLVED:** Notifications section now points to `GET /api/v1/auth/realtime-token` for minting.
- [x] [Review][Patch] Doc: no contract for expiry-while-connected (does Realtime drop at `exp`?), no concrete refresh margin (client uses 60 s), "exchange" wording misdescribes (nothing is exchanged — `rawJwt` unused), and the claim list omits the auto-added `iat` [docs/api-contracts.md:78] [blind-hunter] **RESOLVED:** endpoint section now documents the refresh margin, auto-added `iat`, and the 403 (technician) response.
- [x] [Review][Patch] Test hardcodes `3600` instead of deriving from `REALTIME_TOKEN_TTL_SECONDS` — a TTL change would silently diverge test from code [src/auth/auth.service.spec.ts:918] [blind-hunter] **RESOLVED:** constant exported and used by the tests.

<!-- dismissed as noise: 8 — 500-on-signAsync-internal-error (matches all other endpoints' behaviour); no-sub-token edge (requires already holding the secret; RLS keys on sub so it grants nothing); second-token-store drift (FE realtimeToken.ts registers a 401-reset hook — verified); minted-token-acceptance (covered by pending Task 0 device spike); no rate limit on mint (JWT-gated, HMAC sign is cheap); no Cache-Control (no intermediary cache in path, RN fetch does not cache); expiresAt naming (repo convention genuinely mixed); dangling story refs (consistent with existing doc style). -->

<!-- bmad-code-review 2026-09-09 — fenzo-app Story 3.3 implementation (uncommitted diff, 15 files, +1095/−2; useCreateCustomer.ts excluded as unrelated). 4 layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor (full mode). -->

- [x] [Review][Decision] Absolute-imports mandate vs codebase reality — CLAUDE.md and the spec Design Note mandate `@` aliases in all new files, but **zero of 229 source files use a project alias** (the only match is a doc comment in `ApiService.ts`); jest.config.js has no `moduleNameMapper`, so aliases would not even resolve in tests. Converting the 15 new files would need a jest mapper added and would make them the only alias users in the repo. **RESOLVED (keep-relative chosen, 2026-09-09):** new files keep relative imports matching the whole codebase; the mandate is amended in fenzo-app CLAUDE.md and the Design Note below records the decision.
- [x] [Review][Decision] Topic derived from the profile store, not the auth store — the frozen Always constraint says derive the topic from the **auth-store session** and subscribe to the auth store, but `useAuth`'s `Session` is `{ role, tenantId }` and carries no user id, so the prescribed source cannot supply `userId`. Side effect: socket startup now depends on `GET /users/me` succeeding, not just on having a valid session. **RESOLVED (bless-profile-store chosen, 2026-09-09):** frozen constraint renegotiated with human approval — the topic derives from the profile store's user id (documented in the Boundaries section); the `/users/me` dependency is accepted as part of the silent-degradation contract.
- [x] [Review][Decision] `StatusBanner` renders a `Bell` icon vs frozen Never "Do not implement the bell icon…" — the constraint targets Story 3.4's notifications bell button/badge, but this is the literal reserved phrase. **RESOLVED (keep-Bell chosen, 2026-09-09):** the Never is read as Story 3.4's bell button/badge UI scope, not banner iconography; no code change.
- [x] [Review][Patch] setupChannel mid-flight race — after `await getRealtimeToken()` the code re-checks only `disposed`/topic, never `AppState` or `channelRef.current`: (1) background during the token fetch → socket subscribed and left open while backgrounded (AC violation); (2) rapid active→inactive→active flap → two overlapping setups both create channels, the first is overwritten in `channelRef` and leaks permanently — background teardown only removes `channelRef.current` [useOwnerNotifications.ts:145-166] (high) **RESOLVED:** both gates added — `shouldSubscribe(AppState.currentState)` re-checked before creating the channel AND in the post-await adopt check (which now also discards a loser when `channelRef.current` is already set); two new tests pin both traces (background-during-exchange never opens a socket; flap adopts the winner and tears the loser down).
- [x] [Review][Patch] Event after background teardown still raises banner + fires both force-refetches — `handleJobStatusEvent` checks only `topicRef`, which background teardown does not clear; add an AppState gate in the handler (+ test that a backgrounded app shows nothing on an in-flight event) [useOwnerNotifications.ts:106-125] (low) **RESOLVED:** handler now returns early when `!shouldSubscribe(AppState.currentState)`; test added asserting no banner and no refetch when an in-flight event lands after background teardown. (Nulling `topicRef` in teardown was rejected — it would break the foreground re-subscribe path.)
- [x] [Review][Patch] Banner swallows touches for ~4 s — absolute-positioned overlay has no `pointerEvents`, so header buttons/list rows under it are untappable until auto-dismiss; add `pointerEvents="box-none"` [src/components/StatusBanner.tsx:25] (medium) **RESOLVED:** `pointerEvents="box-none"` on the overlay; probe test asserts it.
- [x] [Review][Patch] `STEP_LABELS[step] ?? step` resolves inherited prototype keys — `step: 'toString'` yields the inherited function and the banner renders its source; use `Object.hasOwn` [notificationBannerModel.ts:102] (low) **RESOLVED:** `Object.hasOwn` guard; tests pin `toString`/`constructor` rendering raw.
- [x] [Review][Patch] `removeChannel` promise rejection unhandled on every teardown (background/logout/user switch) — add `.catch` log [supabaseRealtime.ts:89] (low) **RESOLVED:** `.catch` warn added; test pins rejection swallowed.
- [x] [Review][Patch] Concurrent `getRealtimeToken` callers race a cold/stale cache → duplicate `/auth/realtime-token` exchanges (hook setup + supabase-js `accessToken` callback); share the in-flight promise [realtimeToken.ts:39-60] (low) **RESOLVED:** shared `pending` promise (cleared in `finally`); test pins one exchange for two concurrent callers.
- [x] [Review][Patch] Missing trailing newlines on all 8 new files (verified; `\ No newline at end of file` across the diff) (low) **RESOLVED:** all changed files end with a newline now (package.json included).
- [x] [Review][Patch] `enabled` is a denylist (`!isTechnician`) — bootstrap (session null) and any future non-technician role enable the hook (currently inert because `userId` is null, but the allowlist `session?.role === 'owner'` is strictly safer) [OwnerRealtimeBridge.tsx] (low) **RESOLVED:** allowlist — `isOwner = session?.role === 'owner'` drives both `enabled` and the render gate; bootstrap-null test added.
- [x] [Review][Patch] `realtimeToken`'s cache/expiry contract never executed by any test (fresh-cache short-circuit, margin re-exchange, unparsable `expiresAt` → null, failure → null, `runAllResets` clears) — a regression there dies into log-only silence with CI green [realtimeToken.ts] (medium) **RESOLVED:** new `src/services/realtimeToken.test.ts` — 7 tests covering all of the above plus the concurrent-exchange dedup.
- [x] [Review][Patch] Private-channel contract never executed by any test — the one test touching it asserts its own mock (both sides of the topic comparison come from the test's hand-copied formula); assert the real `ownerNotificationsTopic` output, `config: { private: true }`, and the `accessToken` callback mapping (`getRealtimeToken()` → token, null → `''`) [supabaseRealtime.ts] (medium) **RESOLVED:** new `src/services/supabaseRealtime.test.ts` — createClient options (auth bypassed, accessToken fn), topic format, `private: true` config, exchanged-token/`''` mapping, and removeChannel teardown all asserted against the real module.
- [x] [Review][Patch] `StatusBanner` itself untested (inset offset, text, alert role) and `OwnerRealtimeBridge.test.tsx` claims "StatusBanner itself is covered by its own probe" — no such test exists anywhere [OwnerRealtimeBridge.test.tsx:4-6] (low) **RESOLVED:** new `src/components/StatusBanner.test.tsx` (alert role, label, box-none, inset anchoring, text, null passthrough); the bridge test's header now points at the real file.
- [x] [Review][Patch] Spec bookkeeping — `text-encoding-polyfill` dep and the `loadMyProfile({ force: true })` event extension are user-approved (2026-09-09) but not renegotiated into the frozen Never/Approach text, so spec and code formally contradict [spec frozen sections] (low) **RESOLVED:** frozen sections renegotiated with human approval — Never now records the `text-encoding-polyfill` addition (spike-proven), the Always event bullet records the profile-store extension, the I/O matrix row updated; plus the two decision renegotiations (topic-from-profile-store; relative-imports decision recorded in the Design Note and fenzo-app CLAUDE.md).
- [x] [Review][Defer] No recovery path for a dead socket — `CHANNEL_ERROR`/`TIMED_OUT` log-only, `CLOSED` unhandled; supabase-js auto-reconnect covers most cases, auth-rejection loops don't [useOwnerNotifications.ts:154-158] — deferred, revisit with push in Story 3.4
- [x] [Review][Defer] No event-type filtering — every INSERT on the topic becomes a job-status banner; matters when Story 3.4 adds non-status notification types [useOwnerNotifications.ts:106] — deferred, Story 3.4 scope
- [x] [Review][Defer] `handleJobStatusEvent` not exported/pure — Phase 2 "swappable seam" is weaker than the Design Note prescribes (closure, `(topic, message)` signature); reshape when the FCM handler lands [useOwnerNotifications.ts:106] — deferred, Story 3.4 scope

<!-- dismissed as noise: 10 — banner left after user-switch cleanup (the only user-switch path is the 401 reset, whose registerReset callback clears the banner — verified); cached token not cleared on user switch (all logout paths run runAllResets — verified in MoreScreen); empty-string accessToken fallback (join fails into the log-only callback — the designed silent degradation); response token not validated (BE contract is ours; a bad token dies into the same silent path); hardcoded SUPABASE_* coords (spec prescribes plain sibling constants, no env lib); no refetch debounce (user-approved trade-off, FUTURE OPTIMIZATION recorded in code); long-lived socket token expiry (server disconnects at exp → reconnect re-invokes the accessToken callback); docs not updated (fenzo-app has no docs surface; this story file is the record); unhandled refetch rejections (loadJobs/loadMyProfile catch internally — verified useJobs.ts:167, useMyProfile.ts:101); module-level createClient runs for technicians (AC intent met at hook level — no socket, subscription, or exchange; barrel import is unavoidable). -->

## Suggested Review Order

1. `src/services/supabaseRealtime.ts` — client options (`persistSession: false`, `accessToken`), publishable key from config, channel `private: true`.
2. `useOwnerNotifications.ts` — AppState gate, topic-from-session, event → force-refetch, resetRegistry + auth-store teardown.
3. `App.tsx` — bridge component mounted **only** in the owner `else` branch (not at top level, not in the technician branch).
4. `StatusBanner` — design-system tokens, auto-dismiss.
5. Config diff — no secret material (`service_role` must not appear anywhere in `src/`).

## Dev Agent Record

### Debug Log (Task 0 device spike, 2026-09-09)

Live device run against the local fenzit-be (`http://192.168.1.218:3000/api/v1`) + Supabase
project `pnlvreaijzslfymlnoti`, owner Rohit on the Jobs tab, technician advancing steps on
JB-2026-0003 from a second device session. Findings, in the order they were proven:

- **`react-native-url-polyfill` is REQUIRED, not optional** (resolved the spike's open
  question): supabase-js's constructor rewrites the realtime URL's protocol
  (`realtimeUrl.protocol = ...`), but Hermes's built-in `URL` exposes `protocol` as a getter
  only → crash at module import ("Cannot assign to property 'protocol' which has only a
  getter"). `auto` mode installs it only when globals are missing, so jest/node untouched.
- **`text-encoding-polyfill` also REQUIRED** (found live): "Broadcast from Database" delivers
  messages as BINARY frames and realtime-js's `_binaryDecode` needs `TextDecoder`, which
  Hermes doesn't ship → every incoming broadcast crashed with "Property 'TextDecoder' doesn't
  exist". Same guarded-require pattern as the URL polyfill.
- **Token exchange + topic match verified**: login JWT → `GET /auth/realtime-token` → minted
  token → `SUBSCRIBED` on `user:<owner_id>:notifications` (private channel, RLS-authorized).
- **THREE-level payload nesting discovered** (the story's "raw row" wording was off by two
  wrappers): `on('broadcast')` delivers `{ type: 'broadcast', event: 'INSERT', payload:
  ENVELOPE, meta }`, ENVELOPE is the broadcast_changes `{ id, table, schema, operation,
  old_record, record }`, `record` is the raw `notifications` row, and the RPC's JSONB
  (job_number/step/technician_name) sits at `record.payload`. First device test showed the
  generic fallback banner because the code unwrapped only two levels — fixed and re-verified
  on device: full banner "Ashish · JB-2026-0003 · Completed".
- **Post-spec extension (user-approved during the spike):** the owner was sitting on the Home
  tab, which renders from the profile store (`GET /users/me`), a DIFFERENT store from the
  Jobs tab's — the spec's jobs-store refetch alone left Home's cards stale. The event handler
  now force-refreshes BOTH stores (`loadJobs({ force: true })` + `loadMyProfile({ force: true })`).
  User re-tested and confirmed both tabs update live.
- **FUTURE OPTIMIZATION (noted at user request):** `/users/me` is the heavy endpoint (full
  roster + customers/jobs pages, ~25–40KB plateau from the 50-row page caps) fetched to flip
  one status badge — fine at one event per technician step. If event frequency ever grows
  (Story 3.4 push, many technicians), add a lightweight summary endpoint (counts + today's
  jobs only) and point the handler at it instead. Recorded in the handler's comment too.

### Completion Notes

- All six tasks implemented and verified; every AC exercised on device (foreground live
  update + banner, background teardown/foreground re-subscribe via AppState listener,
  silent degradation paths log-only) except the technician-safety AC, which is automated
  (see tests below) rather than device-tested.
- **Dependency deviation from the Boundaries constraint (line 50), user-approved:** the spec
  anticipated only `@supabase/supabase-js` (+ url-polyfill if the spike proved it needed).
  The spike proved BOTH polyfills needed — `react-native-url-polyfill` AND
  `text-encoding-polyfill` (binary broadcast frames, Hermes lacks TextDecoder). Both are
  guarded (`auto` mode / `typeof` check), so jest/node are unaffected. User installed
  `text-encoding-polyfill` via `bun add` after the live crash.
- `jest.config.js` gained `react-native-url-polyfill` in `transformIgnorePatterns` (raw ESM
  at "main"; the `/mock` subpath routed in jest.setup.js resolves inside the ESM build).
- Lifecycle covers every teardown the ACs name: any non-`'active'` AppState (`'inactive'`
  counts as background) → `removeChannel`; profile-store reset / user switch → channel torn
  down and rebuilt from the new topic, stale-topic events dropped; global 401 reset via
  `registerReset` (also clears the cached realtime token); effect unmount cleanup. The
  `supabaseRealtime` singleton client persists but ends up channel-less — that is the
  intended shape (nothing persists to MMKV; a killed app simply drops the socket with the
  process).
- Foreground-only AC is enforced by the pure `shouldSubscribe(state)` gate (unit-tested) —
  iOS nuance preserved: only `'active'` subscribes.
- Lint note (pre-existing repo gap, NOT from this change): `bun run lint` fails repo-wide —
  the script exists but fenzo-app has no ESLint config file. Typecheck clean
  (`bunx tsc --noEmit`) except the pre-existing TS2591 at `src/config/index.ts`.
- Validation: full suite green — 75 suites / 653 tests (`bun run test`) at implementation;
  78 suites / 674 tests after the 2026-09-09 code-review patches added three contract
  suites (realtimeToken, supabaseRealtime, StatusBanner); device spike
  confirmed end-to-end (banner text, Jobs list live, Home cards live, all user-confirmed).
- Out-of-scope uncommitted change noticed in the repo (NOT part of this story, excluded from
  the File List): `src/features/customers/useCreateCustomer.ts` — a React Navigation
  `merge:true` fix (three-arg `navigate` silently drops params). Needs its own commit decision.

### File List

- `package.json` / `bun.lock` — `@supabase/supabase-js@^2.116.0`, `react-native-url-polyfill@^4.0.0`,
  `text-encoding-polyfill@^0.6.7` added (the latter two beyond the original line-50 constraint — user-approved)
- `jest.config.js` — `react-native-url-polyfill` added to `transformIgnorePatterns`
- `src/config/index.ts` — `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` added
- `src/services/supabaseRealtime.ts` — NEW: singleton client (`persistSession: false`,
  `accessToken` → exchanged token), polyfill imports, topic helper, `getOwnerChannel`,
  `teardownOwnerChannel`
- `src/services/realtimeToken.ts` — NEW: in-memory token exchange cache, 60s refresh margin,
  silent-failure contract, 401-reset registration
- `src/services/index.ts` — barrel exports for the new services
- `src/features/notifications/useOwnerNotifications.ts` — NEW: the hook (AppState gate,
  topic-from-profile, banner state, single `handleJobStatusEvent` seam, resetRegistry wiring)
- `src/features/notifications/notificationBannerModel.ts` — NEW: extracted pure model
  (three-level `eventRowPayload` unwrap, `bannerTextFromEvent`, fallback copy, BANNER_VISIBLE_MS)
- `src/features/notifications/OwnerRealtimeBridge.tsx` — NEW: mounts the hook + banner,
  owner-branch only
- `src/components/StatusBanner.tsx` — NEW: transient banner UI (design-system tokens, auto-dismiss)
- `src/App.tsx` — `<OwnerRealtimeBridge />` mounted in the owner branch only
- `src/features/notifications/notificationBannerModel.test.ts` — NEW (payload unwrap, banner text, drift fallback)
- `src/features/notifications/useOwnerNotifications.test.ts` — NEW (lifecycle, AppState
  teardown/re-subscribe, 401 reset, stale-topic drop, force-refetch of BOTH stores, banner timers)
- `src/features/notifications/OwnerRealtimeBridge.test.tsx` — NEW (technician-safety AC:
  disabled session renders nothing, exchanges no token; bootstrap-null session added in review)
- `src/services/realtimeToken.test.ts` — NEW (2026-09-09 review): cache/margin/failure/reset
  contract + concurrent-exchange dedup
- `src/services/supabaseRealtime.test.ts` — NEW (2026-09-09 review): private-channel contract
  (topic format, `private: true`, exchanged-token `accessToken` mapping, removeChannel teardown)
- `src/components/StatusBanner.test.tsx` — NEW (2026-09-09 review): alert role, box-none
  tap-through, inset anchoring, text, null passthrough
- `CLAUDE.md` — 2026-09-09 review: reality note on the absolute-imports section (no source
  file uses aliases; relative imports remain the codebase convention)

### Change Log

- 2026-09-09: Story implemented (config + realtime client + token service + hook + banner +
  bridge + tests); Task 0 device spike run and recorded; post-spec Home-refresh extension
  added (user-approved); status → review pending BMAD code review of the fenzo-app changes.
- 2026-09-09: BMAD code review complete (4 layers, full mode) — 3 decisions resolved (keep
  relative imports; bless profile-store topic derivation; keep the banner Bell), 12 patches
  applied (setupChannel mid-flight race, backgrounded-event gate, banner tap-through,
  prototype-key step lookup, removeChannel catch, token-exchange dedup, trailing newlines,
  allowlist role gate, three new contract test suites, frozen-section renegotiation), 3
  deferred to Story 3.4, 10 dismissed. Suite now 78 suites / 674 tests. Status → done.