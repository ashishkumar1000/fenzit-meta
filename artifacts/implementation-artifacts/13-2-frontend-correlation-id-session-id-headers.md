# Story 13.2: Frontend — Correlation ID & Session ID headers (fenzo-app)

Status: done (implemented + user device-confirmed + tests written + BMAD review applied: 3 patches, 13 dismissed; 2026-09-21; commit pending user consent)

## Story

As a developer/operator,
I want fenzo-app to stamp every API request with a fresh correlation ID and a stable per-launch session ID,
so that any reported issue can be traced to the exact request in the backend logs (13-1) and, when needed, to the whole app sitting that produced it.

## Acceptance Criteria

1. **X-Correlation-ID per request.** Every request leaving the shared `apiClient` carries a fresh v4 UUID in the `X-Correlation-ID` header, minted at request time (not shared/not reused — never `axios.defaults.headers`, which stamps one value on every call; proven concurrency anti-pattern, research [31]).
2. **X-Session-ID per app sitting.** Every request also carries `X-Session-ID`: one UUID, generated once at module load and kept in memory for the app's lifetime (a "sitting"). It is NOT persisted (no storage) and NOT reset on logout — logout does not end the app sitting.
3. **Reuse the existing v4 generator.** Both ids come from `src/utils/idempotency.ts`'s `generateIdempotencyKey()` (zero-dependency UUID v4 ladder) — no new dependency, no `expo-crypto` addition, no `react-native-get-random-values` polyfill.
4. **One sync request interceptor.** Implementation is a single synchronous `apiClient.interceptors.request.use(...)` registered alongside the existing token and deadline interceptors in `src/services/api/apiClient.ts`. No per-call plumbing anywhere.
5. **No other transport is touched.** `src/utils/r2Upload.ts` (presigned R2 PUT, plain `fetch` to a different origin) stays exactly as-is — it must carry no extra headers and does not use `apiClient`, so it is excluded by construction.
6. **Existing behavior unchanged.** Token attach, abort-deadline, response error shaping, idempotency-key generation (still per mutating action, still the same function) all keep working; all existing test suites stay green.
7. **Tests** (after user confirmation, per the test-timing rule): extend `apiClient.test.ts` to assert both headers on a request — fresh per-request correlation id, stable session id across two requests — following the existing patterns.

## Tasks / Subtasks

- [x] Task 1: Correlation/session interceptor (AC: 1–5)
  - [x] Module-level session id in `apiClient.ts` (or a tiny sibling module if the file's responsibilities section needs it): `const sessionId = generateIdempotencyKey()` minted once at import time
  - [x] One sync request interceptor: sets `config.headers['X-Correlation-ID'] = generateIdempotencyKey()` and `config.headers['X-Session-ID'] = sessionId` on every request
  - [x] Update the `apiClient.ts` header comment (Responsibilities + module layout) to name the third interceptor and the header contract
- [x] Task 2: Verify nothing else regresses (AC: 5, 6)
  - [x] `bunx tsc --noEmit` clean; `apiClient.test.ts` (7) + `idempotency.test.ts` green; full suite identical to the clean tree (6 suites / 17 reports-copy-drift failures pre-existing, verified via stash — see Dev Agent Record)
- [x] Task 3: User confirmation on device (test-timing rule) → then Task 4 tests
- [x] Task 4: Tests (AC: 7)

## Dev Notes

- **Backend contract (13-1, shipped):** fenzit-be's `CorrelationInterceptor` reads `x-correlation-id`/`x-session-id`, validates UUID shape (any version, ≤ 64 chars), falls back to a server-minted id, echoes both back, and puts them on every log line. FE sending v4 UUIDs satisfies it; case of the header name is irrelevant (HTTP headers are case-insensitive, and both sides use the lowercase-on-the-wire spelling via axios).
- **"Stable across retries" is a backend-design framing, not a FE mechanic:** the FE mints per axios request; a user-visible retry (e.g. the Reports Retry button) is a new logical attempt and gets a new id — the backend access log still shows each attempt distinctly, and the idempotency key (unchanged, per action) remains the replay-dedup mechanism. Do NOT try to make the correlation id survive a `useReports`-style refetch; that is out of scope and would need caller plumbing the design explicitly rejected.
- **Reuse, don't rename:** `generateIdempotencyKey()` is a plain v4 UUID generator whose name reflects its first consumer. Reusing it here is the locked design ("reusing src/utils/idempotency.ts generator"). If its name grates at the call site, a local alias (`const newUuid = generateIdempotencyKey`) inside `apiClient.ts` is fine; renaming the util itself is NOT (it would churn 6 consumer files for cosmetics).
- **Session id at module import time:** minting at import (not lazily in the interceptor) is intentional — the id exists before the first request and equals "one per app launch" exactly (JS module state). Hermes reload in dev naturally mints a new one; that matches "per sitting".
- **Interceptor order:** register the correlation interceptor BEFORE the deadline interceptor and it can sit anywhere relative to the token interceptor — none of the three read each other's headers. Keep the file's comment blocks in sync.
- **Header-name casing:** axios normalizes header names at send time; set them exactly as `'X-Correlation-ID'` / `'X-Session-ID'` for readability. The backend's Fastify layer lowercases on the wire.
- **No response-side work:** echoing/validation is backend-owned (13-1). The FE does not read `x-correlation-id` back and does not surface it to users — that was considered and dropped (nothing consumes it yet).
- **Testing pattern to copy:** `src/services/api/apiClient.test.ts` (axios-instance-level tests with mocked adapters/interceptors) + `src/utils/idempotency.test.ts` for the generator itself. Test timing rule applies: implement → user confirms → tests.

### Project Structure Notes

- Modified: `src/services/api/apiClient.ts` (+ its test after confirmation). Possibly nothing else — the whole story is one interceptor plus comments.
- No new dependencies. No backend change. No DB change.

### References

- Research (design + evidence): `artifacts/planning-artifacts/research/technical-correlation-id-2026-09-21/research.md` — §2 client section (interceptor pattern [20], shared-defaults anti-pattern [31], generator choice [16][17])
- Backend story (contract to satisfy): `artifacts/implementation-artifacts/13-1-backend-correlation-id-session-id-propagation.md`
- Sprint note (locked design): `artifacts/implementation-artifacts/sprint-status.yaml` epic-13 block

### Review Findings

- [x] [Review][Patch] Session-id continuity across logout is untested — a regression that re-mints the id on logout would pass all 7 tests; add one test: capture session id from a request, run `clearAuthToken()` (mock already wired file-level), request again, assert SAME session id + fresh correlation id [verification-gap + blind-hunter] — FIXED: 4th test added ('does NOT re-mint the session id on logout'); 8/8 in apiClient.test.ts
- [x] [Review][Patch] r2Upload.ts exclusion rationale lives only in apiClient.ts prose — add one sentence to r2Upload.ts's own header comment noting it is also deliberately excluded from correlation/session stamping (presigned PUT carries no extra headers) [blind-hunter] — FIXED
- [x] [Review][Patch] apiClient.ts comment polish: (1) "attach the bearer token, then stamp" implies sequence — order only matches because axios runs request interceptors LIFO; reword to avoid an order claim; (2) define "sitting" — dev reload / JS-context restart / force-kill re-mint, backgrounded app keeps the id [blind-hunter] — FIXED: Responsibilities item 2 rewritten as an order-agnostic list with the LIFO note; "sitting" defined as one JS-context lifetime

### Dismissed findings (13, for the record)

Overwrite of caller-supplied header is by-design (unconditional mint is what keeps stale-config re-dispatches fresh; no caller ever pre-sets the ids); `config.headers ?? {}` guard matches the existing token-interceptor idiom in the same file and the fallback never fires in practice; Math.random-collision rung is theoretical and pre-existing (generator unchanged in this diff); shared-defaults regression already caught by the 3-concurrent uniqueness test (Set size 3); rename/alias of `generateIdempotencyKey` pre-decided in the story (reuse, don't rename); no config re-dispatch path exists in the repo; response-side echo capture explicitly out of scope (locked design); bracket header style matches the existing 401 tests; backend validator confirmed case-insensitive (13-1 completion notes); "one sync interceptor" spec wording already says "alongside the existing token and deadline interceptors"; POST shape covered by the existing login-401 test; abort-deadline section comment verified to exist; adapter-restore handled by the file-level beforeEach re-arming the 401 adapter for every test.

## Dev Agent Record

### Agent Model Used

Claude (GLM, Claude Code session) — 2026-09-21

### Completion Notes List

- **Implementation is exactly the locked design:** one sync request interceptor at the top of `src/services/api/apiClient.ts`'s interceptor list; module-level `const sessionId = generateIdempotencyKey()` minted at import (one per app sitting); per-request `X-Correlation-ID` minted fresh inside the interceptor; `X-Session-ID` set on every request. Set on the request's own config, never shared defaults (research [31] anti-pattern). `r2Upload.ts` untouched (plain `fetch`, different origin, excluded by construction). File comment blocks updated (Responsibilities renumbered 1–4, correlation section comment added).
- **Generator reused, not renamed:** imports `generateIdempotencyKey` from `../../utils/idempotency` (direct file import, not the `utils/index.ts` barrel, to keep the services→utils surface lean). Six existing consumers of the util untouched.
- **Verification:** `bunx tsc --noEmit` clean. `apiClient.test.ts` (7) + `idempotency.test.ts` green. Full jest run WITH the change: 1160/1177, 6 suites failed — identical counts on the STASHED (clean) tree, so all 17 failures are pre-existing: reports-suite copy drift from the "spec compliance patches" commits (d61a5d1, 9e30d3a — user-facing copy like "Pick both dates" → "Date range is required" changed without updating test expectations). NOT caused by this story; belongs to epic-12 follow-up if the user wants it fixed.
- **No new dependencies, no backend change, no DB change.**
- **User device-confirmed 2026-09-21** → tests written same day (test-timing rule): 3 tests added to `apiClient.test.ts` (v4 shape on both headers; fresh correlation id across 3 concurrent requests; stable session id across requests) — 7/7, tsc clean.
- **BMAD review (2026-09-21, 4 layers): 3 patches applied, 13 dismissed, 0 decisions, 0 defers.** Patches: (1) logout-continuity test added — session id unchanged across `clearAuthToken()`, correlation id fresh (8/8 in the file); (2) r2Upload.ts header comment now states its own exclusion from correlation/session stamping; (3) apiClient.ts Responsibilities item 2 rewritten as an order-agnostic list (axios request interceptors run LIFO) + "sitting" defined as one JS-context lifetime. Tests 8/8 + tsc clean after patches.