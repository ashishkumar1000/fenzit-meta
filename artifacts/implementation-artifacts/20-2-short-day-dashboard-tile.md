# Story 20.2: Short-day dashboard tile

Status: ready-for-dev

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

- [ ] Phase A (fenzit-be): `dashboard.ts` counts object gains `shortDay: 0` (+ docblock note); `dashboard-response.model.ts` `DashboardCounts` gains the field with the "reserved" docblock; api-contracts.md dashboard section notes the reserved field. AC: 1, 8
  - [ ] Existing suites stay green: `bun run test` (unit) and the real-DB dashboard integration spec (`npm run test:e2e:real -- --testPathPatterns attendance-dashboard.integration`) — the zero-change assertion is the point: numbers byte-identical to the deployed behaviour.
- [ ] Phase B (fenzo-app): ACs 4, 5, 6
  - [ ] `src/services/resources/attendanceDashboard.ts`: `AttendanceDashboardCounts` gains `shortDay`; `normalizeDashboard` requires it (non-negative integer); header docblock names the four-bucket contract source.
  - [ ] `src/features/attendance/dashboard/dashboardModel.ts`: `KpiTileSpec['key']` union gains `'shortDay'`; `kpiTiles` entries gain `['shortDay', 'Short day']` positioned after `notCheckedIn`. Compiler forces the rest via exhaustiveness.
  - [ ] `src/features/attendance/dashboard/KpiTile.tsx`: `TILE_VISUALS` gains `shortDay` (icon `XCircle`, colours from `colors.status.cancelled`); `visualLabel` gains the case (`colors.status.cancelled.fg`).
  - [ ] `src/features/attendance/dashboard/AttendanceDashboardScreen.tsx`: skeleton placeholder `Array.from({ length: 6 })` → 8.
  - [ ] Existing FE suites (`dashboardModel.test.ts`, `KpiTile.test.tsx`, `AttendanceDashboardScreen.test.tsx`) updated where they pin the five-tile shape — keep `bun run test` green. (Requirement-update, not test-first: standing test-timing rule.)
- [ ] Phase C (fenzit-be): ACs 2, 3, 8
  - [ ] `dashboard.ts` row loop: compute `const isEngineShortDay = outcome.status === 'absent' && row.override?.status == null && outcome.workedMinutes !== null;` and route those rows `shortDay` instead of `notCheckedIn`. Rewrite the two docblocks (`CHECKED_IN_STATUSES` block + the partition comment) to the four-bucket contract.
  - [ ] `dashboard-response.model.ts`: rewrite the reserved docblock to the live contract. Controller swagger description: four-bucket wording. api-contracts.md: same.
- [ ] Device verification (with the user, or on the attached Pixel 6): Hero wala office reads Tracked 51 = Checked in 0 + Not checked in 49 + On leave 1 + Short day 1; tenant-wide 102 sums exactly. AC: 2
- [ ] Test phase (AFTER the user confirms the device numbers — the standing rule): ACs 2, 3
  - [ ] Integration spec: fix the stale "(overlaps included)… never a partition" prose (20-1 deferred item) AND pin the four-bucket partition — rule-7 sub-threshold absent on today, rule-9 absent, rule-1 absent override with instants, weekly_off, holiday, half_day_leave, filtered-by-office sums. Extend the growing attendance journey suite per the memory note.
  - [ ] FE: normalizer malformed/absent `shortDay` fail-closed pins; kpiTiles order/labels; KpiTile visuals + a11y; screen skeleton count. QA-mindset: zero / one / many boundaries, malformed wire values.
- [ ] `/bmad-code-review` before every commit; consent before commit/push, each repo separately (fenzit-be first — never the other way round).

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

### Debug Log References

### Completion Notes List

### File List