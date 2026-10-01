# Story 20.2: Short-day dashboard tile

Status: done

## Story

As an attendance owner,
I want a separate "Short day" tile counting people who punched in AND out but worked below the half-day threshold,
so that the dashboard no longer reads them as "Not checked in" — a person who visibly punched in is not someone who failed to check in.

## The three user rulings (2026-10-01, binding)

1. The tile is named **"Short day"** (plain business English — no "sub-half-day", no "below threshold" on the surface).
2. **Engine-graded only**: a row reaches Short day only when the ENGINE graded it `absent` from a punch-in + punch-out that fell short (FR-10 rule 7). An owner-adjudicated `absent` correction (rule 1 override) and the past-no-check-in `absent` (rule 9) stay in **Not checked in** — the owner's word overrules the tile, always.
3. **Four buckets still sum**: `tracked = checkedIn + notCheckedIn + onLeave + shortDay`, exactly, on every fetch. Short day is a real bucket (short-day rows leave Not checked in), not an overlay.

## Context — why this story exists

The 20-1 follow-up fixed the user-reported "51 vs 50" bug (fenzit-be `14052e7`, deployed and device-verified): a person with a 1.16-minute punch-in/out graded engine `absent` and vanished from every tile. The fix parked them in Not checked in so the three tiles sum. The owner then called that **misleading** — "not checked in" contradicts what the punch log shows. This story splits that outcome into its own bucket properly.

The partition today (deployed, `dashboard.ts`): bucket keyed on OUTCOME STATUS — `checkedIn = {in_progress, present, half_day, worked_on_holiday}`, `onLeave = {leave, half_day_leave}`, everything else `notCheckedIn`. This story carves the rule-7 `absent` outcome out of that "everything else".

## Acceptance Criteria

1. **(BE, additive) Wire contract**: `GET /attendance/dashboard` response `counts` gains `shortDay: number` — a non-negative integer, sent on every response.
2. **(BE, partition flip — ships LAST, see Phasing)** `tracked = checkedIn + notCheckedIn + onLeave + shortDay`, exactly, for every fetch (tenant-wide and office-filtered).
3. **Engine-graded only**:
   - Rule-7 outcome (record has check-in AND effective check-out; engine graded `absent` because worked minutes < `half_day_hours`) counts in **Short day**, not in Not checked in.
   - Rule-1 owner override with `status = 'absent'` stays in **Not checked in** — even when the override carries instants, even when those instants are under threshold.
   - Rule-9 `absent` (past day, no check-in) stays in **Not checked in**.
   - No other status moves: not_checked_in_yet, weekly_off, holiday stay in Not checked in; leave / half_day_leave stay in On leave; late stays a qualifier of checked in.
4. **(FE, tile)** A sixth KPI tile renders the count: label **"Short day"**, same red family the day sheet's Absent badge uses (`colors.status.cancelled`, `XCircle` icon — the KpiTile colour discipline: never drift from the badge the owner already knows), non-interactive, a11y label `"Short day: n"`, no percent pill (the pill belongs to Checked in alone).
5. **(FE, grid)** Tile order: Tracked | Checked in / Not checked in | Short day / Late | On leave / Present card — two columns, no ragged cell. Skeleton blocks go 6 → 8 (4 rows × 2).
6. **(FE, fail-closed normalizer)** `attendanceDashboard.ts` whitelist gains `shortDay`; a malformed or missing `shortDay` rejects the whole fetch (same rule as the other five).
7. **No new bug during the rollout** (the owner's explicit ask): at every moment, every deployed binary sees every tracked person in exactly ONE rendered bucket — never double-counted, never invisible. Enforced by the phasing below, not by hope.
8. **Docs in the same change**: `docs/api-contracts.md` dashboard section, `dashboard-response.model.ts` docblocks, controller swagger description, and the FE `attendanceDashboard.ts` header all describe the four-bucket partition when it goes live.
9. **Explicitly out of scope**: per-office picker stats stay `tracked/checkedIn` only; the reminder RPC's `notCheckedInCount` (raw-instant keyed, past-cutoff nudges) is NOT touched — it answers a different question.

## Phasing — the 3-step rule for a shaped change (mandatory)

This is a CLAUDE.md breaking-shape change (a count's meaning shifts and a field is added): FE and BE deploy independently, so shape changes go in three steps. Each step is its own commit/consent.

- **Phase A — fenzit-be, purely additive**: add `shortDay: 0` to the counts object (always zero; the partition is UNTOUCHED). The old deployed app ignores an unknown counts key (verified: `normalizeDashboard` reads only its five whitelisted fields), so old binaries render exactly today's numbers. The FE normalizer after Phase B REQUIRES the field — this is why BE ships first. Update `dashboard-response.model.ts` docblocks ("reserved — goes live with the partition flip") and api-contracts.md.
- **Phase B — fenzo-app, purely additive**: the tile, model, normalizer whitelist, skeleton count. Against Phase A's wire it renders "Short day: 0" — every tile honest, sums exact. Old binaries never see this code.
- **Phase C — fenzit-be, the flip**: engine-absent rows meeting the Story's detection move `notCheckedIn → shortDay`; docblocks + swagger + api-contracts rewritten to the four-bucket partition. Old binaries (pre-B) now under-report — but the only app is the owner's device inside the sprint window; the device updates with Phase B before Phase C ships. Verify on device.

Then the test phase (see Testing).

**Decision made against the alternative**: shipping Phase C's real tally in Phase A would leave pre-B binaries with short-day people in NO bucket (invisible) — the exact "not misleading" failure this story forbids. Phase A zero-change costs nothing extra.

## Tasks / Subtasks

- [x] Phase A (fenzit-be): `dashboard.ts` counts object gains `shortDay: 0` (+ docblock note); `dashboard-response.model.ts` `DashboardCounts` gains the field with the "reserved" docblock; api-contracts.md dashboard section notes the reserved field. AC: 1, 8
  - [x] Existing suites stay green: `bun run test` (unit) and the real-DB dashboard integration spec (`npm run test:e2e:real -- --testPathPatterns attendance-dashboard.integration`) — the zero-change assertion is the point: numbers byte-identical to the deployed behaviour.
- [x] Phase B (fenzo-app): ACs 4, 5, 6
  - [x] `src/services/resources/attendanceDashboard.ts`: `AttendanceDashboardCounts` gains `shortDay`; `normalizeDashboard` requires it (non-negative integer); header docblock names the four-bucket contract source.
  - [x] `src/features/attendance/dashboard/dashboardModel.ts`: `KpiTileSpec['key']` union gains `'shortDay'`; `kpiTiles` entries gain `['shortDay', 'Short day']` positioned after `notCheckedIn`. Compiler forces the rest via exhaustiveness.
  - [x] `src/features/attendance/dashboard/KpiTile.tsx`: `TILE_VISUALS` gains `shortDay` (icon `XCircle`, colours from `colors.status.cancelled`); `visualLabel` gains the case (`colors.status.cancelled.fg`).
  - [x] `src/features/attendance/dashboard/AttendanceDashboardScreen.tsx`: skeleton placeholder count goes 6 → 7 (settled cells — six tiles + the present card; the spec's 8 was corrected by the review, see Deviation D-3).
  - [x] Existing FE suites (`dashboardModel.test.ts`, `KpiTile.test.tsx`, `AttendanceDashboardScreen.test.tsx`) updated where they pin the five-tile shape — keep `bun run test` green. (Requirement-update, not test-first: standing test-timing rule.)
- [x] Phase C (fenzit-be): ACs 2, 3, 8
  - [x] `dashboard.ts` row loop: the partition branch routes rule-7 engine-graded absents (`outcome.status === 'absent' && row.override?.status == null && outcome.workedMinutes !== null`) into `shortDay` instead of `notCheckedIn`. Docblocks (`CHECKED_IN_STATUSES` block + the partition comment) rewritten to the four-bucket contract.
  - [x] `dashboard-response.model.ts`: the reserved docblock rewritten to the live contract. Controller swagger description: four-bucket wording. api-contracts.md: same.
- [x] Device verification (on the attached Pixel 6, with mock data; per the user's "put all 100 users in some or other catrogeory and verify" every dummy lands in a bucket): All offices 102 = 10 checkedIn + 1 notCheckedIn + 90 shortDay + 1 onLeave; Hero wala 51 = 5 + 0 + 45 + 1; Yuka 51 = 5 + 1 + 45 + 0; Yuka1 tracked-0 empty state. AC: 2
- [x] Test phase (user re-opened it after device sign-off: "keep the mock data for today's verification, commit after review ...... write test cases"). ACs 2, 3
  - [x] Integration spec: the tiles probe now pins the six-tile PARTITION (sum asserted) and a new real-DB leg grades a rule-7 sub-half-day pair AND shows the owner's `absent` override moving the same facts back out. The unknown-office zeroed probe pins `shortDay: 0`.
  - [x] Reads e2e + journey legs: counts pins moved to the six-key envelope (the verification-gap reviewer's catch — they were still five-key against the shipped flip).
  - [x] FE screen suite: fixture envelopes are six-key and partition-consistent; the counts test pins all six pairings including `Short day: 1`; a new test holds the pick's fetch to pin shimmer-under-pick.
- [x] `/bmad-code-review` before every commit; consent before commit/push, each repo separately (fenzit-be first — never the other way round).

## Dev Notes

### The BE detection, and why it is correct

In the `dashboard.ts` grid loop, a tracked row is engine-short-day iff:

```ts
outcome.status === 'absent' && row.override?.status == null && outcome.workedMinutes !== null
```

Walking the engine (first-match-wins, `day-status.model.ts`): the `absent` status escapes from exactly three rules — rule 1 (override `status === 'absent'`: excluded by the `override?.status == null` guard, even when the override carries instants) — rule 7 (check-in + check-out under threshold: `workedMinutes` is always a non-null number there — the only `absent` with one) — and rule 9 (past, no check-in: `workedMinutes` is `null`, same as every other no-punch status). So the three-way check uniquely selects rule 7. Do NOT re-derive instants in the dashboard — read it off the outcome the engine already produced (one engine, no drift).

Edge — a times-only correction (override with instants, `status: null`) that still grades under threshold: the ENGINE still grades it `absent`, and it lands in Short day. That follows ruling 2 and the tile/calendar invariant: the day sheet shows the same engine grade. An owner who wants that row NOT short-day sets the status override.

### What must NOT change

- `checkedInPct` / present card: share of the checked-in bucket over tracked — untouched.
- Per-office `OfficeCard`/`OfficeFilterSheet` subtitles: `tracked/checked in` only (ruling; adding a per-office shortDay count is future work if the owner ever asks).
- The reminder RPC `notCheckedInCount` in `src/attendance/reminder-sql*` — different semantics on purpose (dashboard.ts docblock already records the divergence; 20-1 deferred-work item 2).
- The engine itself (`computeDayStatus`, rules, graders): zero changes — this is a dashboard-bucketing story only.
- `Late` remains a checked-in qualifier (`if (checkedIn && outcome.isLate)`).

### FE touch surface (verified while writing this story)

- `attendanceDashboard.ts` — the normalizer reads ONLY whitelisted keys and ignores extras: additive-safe for old binaries; the six-field whitelist makes the NEW FE demand Phase A's field.
- `dashboardModel.ts` — `KpiTileSpec` union + the `kpiTiles` entries array are the only two edits; `pct` stays null for `shortDay` (the `key === 'checkedIn'` ternary handles it).
- `KpiTile.tsx` — `TILE_VISUALS` is a `Record<Exclude<TileKey,'tracked'>, …>` mapping and `visualLabel` a switch: TypeScript's exhaustiveness makes a missed case a compile error, not a silent drift.
- `AttendanceDashboardScreen.tsx` — only the skeleton `Array.from({ length: 6 })` constant; tiles render from the model.
- No new icon or dependency: `XCircle` is already imported in `dayStatusVisual.ts`; the red family already rides `Badge`/`FlagStrip` (`fakeLocationAttempt` uses `cancelled`) — hue is known to owners from fake-location, but here it keys to the ABSENT badge the day sheet shows. Keep the tile copy to family hue only (count/label), no judgement.

### Regression risk register (the owner's "don't introduce any new bug")

- Double-count: someone in BOTH notCheckedIn and shortDay on a new binary — impossible by Phase C's if/else (rows MOVE, not copy).
- Invisible person (old binary post-Phase-C): prevented by ordering Phase C after Phase B's device reach.
- Sum≠tracked on any binary: Phase A keeps zeros; assert the sum in the integration spec and on the device probe.
- Normalizer crash on old BE: only if FE ships before Phase A — forbidden by the order.
- Skeleton/layout jump: the grid swap uses the same `tileWidth` math; 8 blocks match the 4 real rows.

### Project Structure Notes

- fenzit-be: `src/attendance/dashboard.ts` (~250 lines, fine under the 300 limit with the flip); NestJS-only logic, no new SQL function, no RPC (AD-3 continuation).
- fenzo-app: feature dir `src/features/attendance/dashboard/`, contract file `src/services/resources/attendanceDashboard.ts`; relative imports per repo reality (no aliases); theme tokens only.
- Backend owns the bucketing semantics (the FE renders the envelope, never recounts) — FE is the boundary adapter with fail-closed parsing.

### References

- [Source: workspace/core/backend/fenzit-be/src/attendance/dashboard.ts] — the deployed three-bucket partition + grid loop (Phase C's edit site).
- [Source: workspace/core/backend/fenzit-be/src/attendance/day-status.model.ts] — rules 1/7/9 (the absent tri-source), `gradeWorked` GR-3.
- [Source: workspace/core/backend/fenzit-be/src/attendance/dashboard-response.model.ts] — `DashboardCounts`, the FE's named contract source.
- [Source: workspace/core/backend/fenzit-be/docs/api-contracts.md#dashboard] — partition wording to update.
- [Source: workspace/core/frontend/fenzo-app/src/services/resources/attendanceDashboard.ts] — fail-closed normalizer + wire facts.
- [Source: workspace/core/frontend/fenzo-app/src/features/attendance/dashboard/dashboardModel.ts, KpiTile.tsx, AttendanceDashboardScreen.tsx] — tile model, visuals map, grid/skeleton.
- [Source: workspace/core/frontend/fenzo-app/src/features/attendance/calendar/dayStatusVisual.ts] — `absent → cancelled / XCircle`, the parity source for the tile's family.
- [Source: artifacts/implementation-artifacts/20-1-frontend-leave-day-sheet-actions-and-owner-attention.md] — the 51-vs-50 root cause + deployed fix record.
- [Source: artifacts/implementation-artifacts/deferred-work.md] — the two test-phase pins this story's test phase absorbs.

## Dev Agent Record

### Agent Model Used

Claude (Opus 5.5)

### Debug Log References

- BE integration spec: `npm run test:e2e:real -- --testPathPatterns attendance-dashboard.integration` — 11/11 green after corrections (13.5 s).
- BE gates at commit time: `bun run build` exit 0; `bun run test` 1421/1421 (90 suites); reads e2e `bunx jest --config ./test/jest-e2e.json test/attendance-reads.e2e-spec.ts` 16/16; journey e2e 2/2 (real DB).
- FE gates at commit time: `bun run test` 2919/2919 (235 suites); dashboard dir suites 82/82 (9 suites).

### Completion Notes List

**Implementation.** Three shipped commits + two test-phase commits:

1. `fenzit-be` `a829291` (phase A): counts carry reserved `shortDay: 0` — pushed + Render-deployed.
2. `fenzit-be` `50c366c` (phase C, the flip): the four-bucket partition goes live — pushed + Render-deployed the same day (device had the phase-B tile build running, see deviation D-1). Docs (headers, response-model docblocks, api-contracts.md) rewritten to "the FOUR buckets partition tracked; rows move, never copy; late is a qualifier of checkedIn, not a bucket".
3. `fenzo-app` `3c0f7f2` (phase B, committed with the user's post-review approval): the Short day tile (fail-closed normalizer, model entry, KpiTile visuals — cancelled family + XCircle) + the shimmer discipline (one refcounted `runWithShimmer` wrapping both user-initiated paths: Refresh press AND office pick) + skeleton geometry 7 placeholders at KpiTile minHeight.
4. `fenzit-be` `250e0a7` (test phase, after the user re-opened tests): integration-spec partition pins + the rule-7/override leg; six-key catch-up of the reads-e2e and journey pins; journey UUID-flake fix; docs/comments polish.

**Detection predicate stays as specced** (`absent` + no override status + `workedMinutes !== null`) — auditor re-walked rules 1/7/9 and confirmed only rule 7 escapes it. The `== null` over `=== null` matters: an override object with `status: null` (note-only or instants-only override) must NOT block the engine grade.

**Device verification (the user's mock-data session).** User authorised moving the Hero wala weekly off from Friday to Sunday (`attendance_weekly_off_defaults.days '{5}'→'{7}'`, row `dc1b44b7-4e58-45e2-bc18-d172a932a684`) so Short day was demonstrable today (on a weekly-off day rule 3 outranks rule 7 — Short day is IMPOSSIBLE on an off day). All 100 dummies (Loadtest H01–H50 @ Hero wala, Y01–Y50 @ Yuka) planted: 45 closed sub-half-day pairs per office → Short day, 5 open in-progress per office → Checked in; Suresh no-punch → Not checked in; Arya on leave → On leave. Verified per office on device — sums exact everywhere (Hero wala 51 = 5+0+45+1; Yuka 51 = 5+1+45+0; Yuka1 empty state; tenant 102 = 10+1+90+1, Late 10 as a rider inside Checked in).

**Shimmer verification (the user's reported issue).** Refresh press → card shimmer → settle correct; office pick → field updates instantly, previous office's numbers never shown under the picked name; pull-to-refresh → spinner only; focus/AppState refetches silent. Verified across Yuka / All offices / Hero wala / Yuka1 legs. uiautomator dump never idles during shimmer — verified via `adb exec-out screencap`.

**/bmad-code-review record (4 agents, all findings actioned or triaged).** Blind-hunter's 17 findings: 15 dismissed with reasons below; stale five-bucket module docs (fixed before the flip's test commit) and the skeleton 6→8-vs-7-cell mismatch (fixed to 7) were the two real ones. Acceptance-auditor: code conformant to all rulings; stale-doc finds. Edge-case-hunter: confirmed the skeleton fix, dismissed the tracked-0/empty-scope shape and the `== null` style. Verification-gap (4 findings): (a) five-key pins red against the shipped flip — the mocked reads-e2e gate (`Object.keys(counts)` pinned to five) was genuinely red-since-flip; both e2e specs re-pinned six-key; (b) rule-7 branch never observed above 0 — covered by the new integration leg; (c) office-pick shimmer untested — covered by the new held-fetch screen test; (d) screen fixture envelopes invalid (five-key, and 3+2+1 ≠ tracked 5) — fixed partition-consistent six-key with a `Short day: 1` pairing pin.

**Dismissed review findings (recorded so they don't come back):** fail-closed FE vs old-BE normalizer (deliberate phased ship — the docblock's older-deployed-BE tolerance is namespaced to `offices`; the counts demand is load-bearing by design); shimmerRefs on unmount (harmless no-op; fresh refs per mount); picker stats staying tracked/checkedIn (ruling 9); empty-scope pick shimmer (no previous numbers to hide — accepted minor posture); `workedMinutes === 0` routing (rule 7 grades it absent → Short day is engine-correct: 0 worked minutes is a short day, the punch is the point); `== null` vs `=== null` mixing (TypeScript guarantees the narrowing).

**Deviations from the spec as written:**

- **D-1 — ship order was A → C → B-committed, not A → B → C.** The user resequenced to device-first ("test on device", then committed the FE only after review approval). During the window where the flip WAS rendered by the old FE, the owner's single device already ran the phase-B build (tile installed, numbers honest) before we let the flip verify on-device; no other binary exists pre-launch. The invisible-person risk AC 7 guards holds only for binaries, not for the one device — recorded openly as the price of the resequencing.
- **D-2 — the user-mock session kept today's data.** All 100 dummy punch rows + today's `attendance_attempts` stay in the DB, and the Hero wala weekly off stays Sunday, until the user says otherwise (their "Keep it for now"). Removal recipe when approved: delete `attendance_attempts`/`attendance_records` for today where `employee_id in (select id from users where name like 'Loadtest%')`, restore `attendance_weekly_off_defaults.days = '{5}'` on `dc1b44b7-4e58-45e2-bc18-d172a932a684`. NOTE: flipping the weekly off BACK to Friday re-grades today's 90 short days to `worked_on_holiday` (grading computes on read — rule 3 outranks rule 7): the tiles re-read Checked in 100, Not checked in 1, Short day 0. Nobody is lost.
- **D-3 — skeleton 8 → 7 placeholders** (AC 5 said 8/4-rows × 2). The settled grid is 7 cells: six tiles + the present card, in ragged 2/2/2/1 rows. The review's edge-case-hunter caught the placeholder shaping a grid one row richer than what replaces it; fixed and commented at the constant.
- **D-4 — the user-directed rider:** shimmer-on-pick (scope change must never show the old office's numbers under the new office's name) was not in the story's ACs; added as the spec's D9/D10 postures generalized, then device-verified and test-pinned.
- **AC 3 "even when the override carries instants"** is unachievable as written — the DB pair-check (`attendance_day_overrides_pair_check`) forbids manual instants beside a non-null status. The test leg therefore exercises the achievable edge: a status-only `absent` override riding the SAME punch facts — and the test is stronger for it (same facts flip bucket on pure owner's-word). (Correcting the TEST against an impossible DB state — the test alone changed, the requirement's intent unchanged.)

**Deferred (recorded, not blocking):** `useDashboardData` has no hook-level shimmer unit test beyond the screen-level pins (the two user-visible paths now both have held-fetch screen tests); no new-FE/old-BE posture simulation (the phasing story stands on the deploy ordering instead); the reminder RPC's `notCheckedInCount` divergence stays documented in `dashboard.ts` (20-1 deferred item 2, untouched per AC 9); `test/integration/attendance-leave.integration.spec.ts` has a pre-existing helper flake (`Invalid time value` in its own `addDays`) — unrelated surface, not this story's scope.

### File List

- fenzit-be — `a829291`, `50c366c`, `250e0a7`: `src/attendance/dashboard.ts`, `src/attendance/dashboard-response.model.ts`, `src/attendance/dashboard.controller.ts` (swagger), `docs/api-contracts.md`, `test/integration/attendance-dashboard.integration.spec.ts`, `test/attendance-reads.e2e-spec.ts`, `test/attendance-journey.e2e-spec.ts`
- fenzo-app — `3c0f7f2`: `src/services/resources/attendanceDashboard.ts` (+ test), `src/features/attendance/dashboard/dashboardModel.ts` (+ test), `src/features/attendance/dashboard/KpiTile.tsx` (+ test), `src/features/attendance/dashboard/useDashboardData.ts`, `src/features/attendance/dashboard/AttendanceDashboardScreen.tsx` (+ test)
- meta — this story file, `sprint-status.yaml`

### Change Log

- 2026-10-01 · Phases A + C deployed to fenzit-be (shortDay reserved, then live) with device verification per office.
- 2026-10-02 · Phase B committed to fenzo-app after the review; shimmer-under-refresh verified on device first; mock data planted and every dummy bucketed.
- 2026-10-02 · Test phase committed to fenzit-be (`250e0a7`) — six-key e2e pins, the rule-7/override integration leg, the journey flake fix; story marked done.
- 2026-10-02 · All three repos PUSHED (user consent): fenzit-be `250e0a7` (Render auto-deploys it — tests/docs only, behaviour-identical; `api.fenzit.com/api/v1/health` 200), fenzo-app `3c0f7f2`, meta `5aa6aeb`.