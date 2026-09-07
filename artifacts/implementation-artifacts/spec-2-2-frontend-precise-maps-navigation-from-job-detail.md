---
title: 'Frontend — Precise maps navigation from job detail'
type: 'feature'
created: '2026-09-07'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: 'e7a3189b9c7b3cdd00c326c14e2f41f78375cf62'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Story 2.1 exposed the customer's saved `latitude`/`longitude` in `GET /jobs/:id`'s customer profile, but `fenzo-app` still opens the maps app with a text query (`maps:0,0?q=<address, city>` / `geo:0,0?q=...`) — a text-match guess that can land the technician on the wrong door. The coordinates ride in the response unused.

**Approach:** Teach `openMaps` (`src/utils/linking.ts`) to build a coordinate-based deep link when usable coordinates are supplied, and have `TechJobDetailContent.tsx`'s address row pass the customer's coordinates through. When coordinates are absent (or only half-present), the function falls back to today's exact text-query behavior. Zero visual change anywhere — the row looks identical in both cases (UX-DR6); only the underlying URL differs.

## Boundaries & Constraints

**Always:**
- Extend `JobDetailCustomer` (`src/services/resources/jobs.ts:212-220`) with `latitude: number | null; longitude: number | null;` — an exact mirror of Story 2.1's response shape (camelCase, both always present, null when absent). Update every local `JobDetail` fixture TypeScript forces.
- `openMaps` gains one optional third parameter — `coords?: { latitude: number | null; longitude: number | null } | null` (a plain object literal typed inline in `linking.ts`; the util must not import from `services`). Coordinates are **usable only when both fields are non-null** — Story 1.3 allows independently-optional columns, so a half-present coordinate pair is not a location.
- Coordinate deep link forms (AC-fixed; iOS form renegotiated 2026-09-07 per review Decision 1): iOS `maps://?q={lat},{lng}` (Apple's documented query form — the `maps:{lat},{lng}` path variant is an undocumented community pattern), Android `geo:{lat},{lng}?q={lat},{lng}` — plain numeric interpolation, no rounding, no `encodeURIComponent` (numbers need no escaping; the `0,0` prefix is deliberately dropped — the device centers on the point itself, not a search box). Text-fallback URL forms stay byte-identical to today.
- Call site (`TechJobDetailContent.tsx:126`) passes `{ latitude: detail.customer.latitude, longitude: detail.customer.longitude }` as the third argument; everything else about the row — MapPin, address text, Navigation icon, `accessibilityLabel="Open in maps"`, press styling — stays untouched (UX-DR6: no "precise vs. approximate" badge).
- Keep `openMaps`' self-swallowing failure contract: `try`/`catch` → `console.warn('[linking] openMaps failed →', ...)`, no throw into the rendering row. Same for the coordinate branch.
- The maps row's render gate stays on `customerAddress` exactly as today. Coordinates improve the link of the row; they never create, hide, or restyle the row.

**Ask First:** None — UX-DR6, the URL forms, and the fallback behavior are all fixed by the epics file's Story 2.2 ACs and `epic-1-context.md`; this is a pure frontend change with no renegotiated UX.

**Never:**
- Do not change the row's visual appearance in either case — no badge, no icon swap, no color change, no toast (UX-DR6).
- Do not fabricate coordinates from anything other than the response's own values — never geocode the address text client-side, never default to a device location.
- Do not touch the Owner-side job detail or any other `openMaps` consumer — `TechJobDetailContent` is the only call site today, and other screens stay out of scope (the util's doc-comment mentions Story 3.2 reuse; that future consumer inherits the new signature naturally).
- Do not touch `openTel` or restructure `linking.ts` beyond the one function — the file's self-swallowing contract for both helpers is the existing convention.
- Do not add a new dependency (no maps SDK, no react-native link helper) — plain `Linking.openURL` deep links, as today.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Customer with coordinates | Job whose customer has non-null `latitude` + `longitude` (Story 2.1) | Maps row opens `maps://?q={lat},{lng}` (iOS) / `geo:{lat},{lng}?q={lat},{lng}` (Android); row visually identical to today | `openURL` rejection → `console.warn`, no throw |
| Customer without coordinates | Both `null` (legacy customer, or free-text creation) | Exact today's fallback: `maps:0,0?q=<address, city>` / `geo:0,0?q=...` text query — unchanged bytes | Same as today |
| Half-present coordinates | Only `latitude` or only `longitude` non-null (allowed by Story 1.3) | Not usable → text-query fallback, identical to the null case; never a fabricated or zero-padded coordinate | N/A |
| No address text, coordinates present | `customer.address` null (row not rendered) | Row stays unrendered — existing gate unchanged; coordinates alone never summon the row | N/A |
| Existing row behaviors | Back nav, other cards, PersonRow phone affordance | Byte-identical rendering; only the URL string passed to `Linking.openURL` differs | N/A |
| `Linking` unavailable / rejects | iOS query rejection, no maps app | Swallowed silently per the file's existing contract (`canOpenURL`-style quiet give-up is not required here — today's `openMaps` doesn't `canOpenURL` and that stays the case) | `console.warn` |

</frozen-after-approval>

## Code Map

- `src/utils/linking.ts:40-55` -- `openMaps`: add optional third `coords` param (named `MapCoordinates` type, exported from `linking.ts` — renegotiated wording per review Decision 2); usable-coords branch builds the coordinate URL (iOS `maps://?q={point}`, Android `geo:{point}?q={point}` per `Platform.select`), else falls through to the existing text-query logic unchanged; update the function doc-comment to describe both modes
- `src/services/resources/jobs.ts:212-220` -- `JobDetailCustomer`: add `latitude: number | null; longitude: number | null;` with the same "null when…" doc-comment style as `address`/`city`
- `src/features/technicianApp/components/TechJobDetailContent.tsx:126` -- maps row `onPress`: pass `{ latitude: detail.customer.latitude, longitude: detail.customer.longitude }` as `openMaps`'s third argument; nothing else in the component changes
- `src/utils/linking.test.ts` (new) -- unit tests with `Linking` mocked: coordinate URL per platform, null-coords text URL, half-present-coords fallback, blank-everything no-op; `openTel` contract pinned too (cheap while the mock is up)
- `src/features/technicianApp/components/TechJobDetailContent.test.tsx` -- extend: press the maps row with a coordinates-bearing fixture → `openURL` received the coordinate URL; press with null coords → the exact text-query URL; fixture gains the two new fields
- Reference: `workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts` -- Story 2.1's response shape this story mirrors (do not touch; already merged)
- Reference: `artifacts/implementation-artifacts/spec-2-1-backend-expose-customer-coordinates-in-job-detail-response.md` -- the backend contract (field names, nullability, always-present keys)

## Tasks & Acceptance

**Execution:**
- [x] `src/utils/linking.ts` -- `openMaps` coordinate branch + optional `coords` param; doc-comment updated
- [x] `src/utils/linking.test.ts` -- new unit suite for `openMaps` (both modes + fallbacks) and `openTel` contract
- [x] `src/services/resources/jobs.ts` -- `JobDetailCustomer` gains the two nullable fields
- [x] `src/features/technicianApp/components/TechJobDetailContent.tsx` -- pass coordinates through on the maps row
- [x] `src/features/technicianApp/components/TechJobDetailContent.test.tsx` -- fixture + press-the-row assertions for both URL modes

**Acceptance Criteria:**
- Given a job whose customer has saved coordinates, when the technician taps the maps row, then `openURL` is called with `maps://?q={lat},{lng}` (iOS) / `geo:{lat},{lng}?q={lat},{lng}` (Android)
- Given a customer with no (or half-present) coordinates, when the row is tapped, then `openURL` is called with exactly today's `maps:0,0?q=...` / `geo:0,0?q=...` text query — unchanged bytes
- Given either case, the row renders identically — no visual difference, no badge (UX-DR6)
- Given any other `openMaps`/`openTel` consumer, the signatures are backward-compatible (new param optional) and their behavior is unchanged

### Review Findings

- [x] [Review][Decision] iOS coordinate URL form is not Apple's documented maps scheme — Apple documents `maps://?q=lat,lng`-style forms; the AC-fixed `maps:{lat},{lng}?q={lat},{lng}` (lat,lng as the path) is a community pattern, unverified on a real device. Options: device-verify the current form, or renegotiate the AC (e.g. `maps://?ll={lat},{lng}&q={lat},{lng}`). Android `geo:` form is documented and fine. → **Resolved 2026-09-07 (owner):** renegotiated to iOS `maps://?q={lat},{lng}` — Apple's documented form; Android unchanged. Code + tests updated.
- [x] [Review][Decision] Named `MapCoordinates` type vs frozen spec's "plain object literal typed inline" [src/utils/linking.ts:40] — the exported named type deviates from the frozen Always bullet's letter; the constraint's intent (self-contained util, no `services` import) is fully satisfied. Keep + record renegotiation, or revert to an inline literal type. → **Resolved 2026-09-07 (owner):** keep the named `MapCoordinates` export; the spec's Always bullet and Code Map were updated to record the renegotiated wording.
- [x] [Review][Patch] Deduplicate `openMaps`' two near-identical open+catch blocks [src/utils/linking.ts:52-87] — one `Platform.select` prefix computation and a single try/catch serve both the coordinate and text branches (also absorbs the `default: 'maps:'` nit). → **Skipped 2026-09-07 (owner-approved):** after Decision 1 renegotiated the iOS form, the two branches build URLs structurally differently — merging them needs abstraction for no real gain.
- [x] [Review][Patch] Add a rejection test for the coordinate branch's try/catch [src/utils/linking.test.ts] — added: a rejected `openURL` with usable coords is logged, never thrown.
- [x] [Review][Patch] openTel contract coverage in the new suite [src/utils/linking.test.ts] — added: rejection-swallow, `canOpenURL` false → nothing dialled, `canOpenURL` scheme-check assertion on the dial path.
- [x] [Review][Patch] Await `openMaps`/`openTel` promises in the sync-assert tests [src/utils/linking.test.ts] — every test now awaits its helper call (survives implementation reordering).
- [x] [Review][Patch] Missing trailing newline in `src/utils/linking.test.ts` — fixed.

## Design Notes

- The "usable coordinates" rule (both non-null) lives inside `openMaps`, not the call site — one rule, one home; callers can't half-use it.
- No `encodeURIComponent` on the coordinate branch is deliberate: lat/lng interpolate to `[0-9.+-]` only. The text branch keeps its encoding as today.
- `openMaps` keeps swallowing its own failures — a rejected maps URL must never break a render-only row (file-level convention, documented at the top of `linking.ts`).
- Cross-repo ordering: Story 2.1 (`fenzit-be`, additive) already merged/deploys first; this story (`fenzo-app`) consumes the field. The FE type treats both fields as always-present-but-nullable, mirroring the backend's stable shape.
- Test note from the repo: jest runs via `bun run test` (never bare `bun test` — RN Flow types break it); add `--watchman=false` if watchman is sandbox-blocked.

## Dev Agent Record

**Agent Model Used:** claude (GLM) via Claude Code, BMAD dev-story workflow — 2026-09-07

**Implementation Plan:**

TDD red-green-refactor. RED: wrote `src/utils/linking.test.ts` first (mocked `react-native` wholesale — `Linking` + a `Platform.select` controlled by a `mockOS` variable, since modern RN exposes `Platform.OS` as a getter) and confirmed 5 coordinate-mode failures against today's `openMaps`. GREEN: implemented the usable-coordinates branch + optional third param in `openMaps`; 14/14 passing. Then type (`JobDetailCustomer`), call site, and component press tests. Two early test-suite issues caught and fixed during RED: the mock initially lacked `canOpenURL` (openTel awaits it before dialing), and the `openTel` dial assertion had to await the promise (the guard-then-await path means `openURL` fires a tick later).

**Debug Log References:**

- `tsc --noEmit` caught 3 additional `JobDetail` fixtures under the root `__tests__/` dir beyond the 2 in `src/` that TS forced at edit time — all 5 updated with `latitude: null, longitude: null`.
- `bun run lint` fails with "no configuration file found" at baseline — the repo has no eslint config file on disk (`eslint .` has nothing to load). Pre-existing, unrelated to this story; not fixed here (adding a config is out of scope).
- Full suite: 71 suites / 618 tests, all passing. `tsc --noEmit` exit 0.

**Completion Notes List:**

- ✅ `openMaps(address, city?, coords?)`: usable coords (both non-null) → `maps:{lat},{lng}?q={lat},{lng}` (iOS) / `geo:...` (Android), verbatim numbers, no `0,0` prefix, no encoding; otherwise byte-identical text-query fallback. Failure-swallowing contract preserved in both branches.
- ✅ `JobDetailCustomer` mirrors Story 2.1's shape exactly (`latitude`/`longitude` always present, nullable). `MapCoordinates` type exported from `linking.ts` (no `services` import in the util).
- ✅ Maps row passes the customer's coordinates through; zero visual change (UX-DR6) — render gate stays on `customerAddress`, no badge.
- ✅ 18 new tests: 14 in `linking.test.ts` (both URL modes, half-present fallbacks, blank no-op, verbatim numbers, rejection swallowing, openTel contract), 4 in `TechJobDetailContent.test.tsx` (press-the-row for coords/null/half-present + identical-render assertion).
- ✅ ACs 1–4 satisfied; no new dependency; no other consumer touched.

### File List

- `src/utils/linking.ts` (modified — `openMaps` coordinate branch, optional `coords` param, exported `MapCoordinates`, doc-comment)
- `src/utils/linking.test.ts` (new — 14 tests)
- `src/services/resources/jobs.ts` (modified — `JobDetailCustomer` gains `latitude`/`longitude`)
- `src/features/technicianApp/components/TechJobDetailContent.tsx` (modified — maps row passes coordinates)
- `src/features/technicianApp/components/TechJobDetailContent.test.tsx` (modified — fixture + 4 new press/render tests)
- `src/features/jobDetail/editJobModel.test.ts` (modified — fixture gains the two fields)
- `src/features/technicianApp/workflowActionBarModel.test.ts` (modified — fixture gains the two fields)
- `__tests__/edit-job-sheet.test.tsx` (modified — fixture gains the two fields)
- `__tests__/job-detail-screen.test.tsx` (modified — fixture gains the two fields)
- `__tests__/tech-job-detail-screen.test.tsx` (modified — fixture gains the two fields)

### Change Log

- 2026-09-07 — Story 2.2 implemented: coordinate deep link in `openMaps` with text-query fallback, coordinates threaded from `JobDetailCustomer` through the technician maps row. 18 new tests; full suite 618 passing; `tsc --noEmit` clean. Lint not runnable (no repo eslint config — pre-existing).
- 2026-09-07 — Review decisions resolved: iOS coordinate form renegotiated to `maps://?q={lat},{lng}` (Apple's documented form; the `maps:{lat},{lng}` path variant was undocumented); named `MapCoordinates` type kept (spec wording renegotiated). Code + tests updated to the new iOS form.
- 2026-09-07 — Review patches applied (4 of 5; dedupe skipped owner-approved): coordinate-branch rejection test, openTel rejection + `canOpenURL`-false + scheme-check coverage, all sync-assert tests now await their helpers, trailing newline fixed. `linking.test.ts` now 17 tests; full suite 71 suites / 621 tests passing; `tsc --noEmit` clean.

## Verification

**Commands:**
- `bun run test -- linking` -- expected: new `linking.test.ts` passes (coordinate + text + fallback cases)
- `bun run test -- TechJobDetailContent` -- expected: extended render/press tests pass for both URL modes
- `bun run test` -- expected: full suite green (no fixture drift failures)
- `bun run lint` -- expected: no new eslint findings in touched files

## Suggested Review Order

**The util change** (the only logic)

- `openMaps`: optional `coords` param, usable-coords rule, coordinate URL branch, fallback preserved byte-identical.
  [`linking.ts:40`](../../workspace/core/frontend/fenzo-app/src/utils/linking.ts#L40)

**Type + call site** (must land together)

- `JobDetailCustomer` gains the two nullable fields mirroring Story 2.1.
  [`jobs.ts:212`](../../workspace/core/frontend/fenzo-app/src/services/resources/jobs.ts#L212)
- Maps row passes the customer's coordinates through.
  [`TechJobDetailContent.tsx:126`](../../workspace/core/frontend/fenzo-app/src/features/technicianApp/components/TechJobDetailContent.tsx#L126)

**Tests**

- Unit: `openMaps` both modes, half-present fallback, blank no-op, `openTel` pin.
  [`linking.test.ts`](../../workspace/core/frontend/fenzo-app/src/utils/linking.test.ts)
- Render: press-the-row assertions for both URL modes.
  [`TechJobDetailContent.test.tsx`](../../workspace/core/frontend/fenzo-app/src/features/technicianApp/components/TechJobDetailContent.test.tsx)
</content>