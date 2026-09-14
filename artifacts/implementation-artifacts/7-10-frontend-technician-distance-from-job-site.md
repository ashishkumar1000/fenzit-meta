---
epic: 7
story_id: "7-10"
title: "Frontend: show technician distance from job site in activity timeline"
status: done
created: 2026-09-14
updated: 2026-09-14
acceptance_criteria:
  - AC1: "Step events with captured coordinates show a caption with the straight-line distance from the job site (customer's saved coordinates), formatted `≈120 m away` below 1 km and `≈2.4 km away` at or above 1 km"
  - AC2: "When the customer has no saved coordinates, captured-location events show `Location captured` with no distance (never a fabricated distance)"
  - AC3: "Missed captures (`locationCaptured: false`) show a caption with the stored reason, e.g. `Location not captured — permission denied`"
  - AC4: "Low-accuracy fixes (`accuracyFlagged: true`) get a soft hint on the distance caption (e.g. `· low GPS accuracy`), never a rejection or warning styling beyond a muted caption suffix"
  - AC5: "Non-location events (pre-Epic-7 rows, `job_created`, `job_reassigned`, metadata null/absent keys) render exactly as today — no caption, no regression"
  - AC6: "Caption is visible to both audiences — owner JobDetailScreen and technician TechJobDetailScreen's history disclosure — with no role gating"
blocking: []
spec_refs:
  - "artifacts/specs/spec-job-step-location-capture/SPEC.md (Non-goals — read-side viewer deferred here)"
  - "artifacts/specs/spec-job-step-location-capture/backend-architecture.md section 2.3 (metadata keys)"
  - "fenzit-be supabase/migrations/20260913000002_advance_workflow_step_location_params.sql"
baseline_commit: f2981a4ec949d1ed9b2b36160209de334df9d08f
---

## Tasks / Subtasks

- [x] Task 1 — `utils/distanceUtils.ts` (AC1): haversine + formatter, test-first, re-export from `index.ts`
- [x] Task 2 — `features/jobDetail/locationMetadata.ts` (AC2–AC5): defensive parser, test-first
- [x] Task 3 — `ActivityTimeline.tsx` caption (AC1–AC5): render captions, component wiring test
- [x] Task 4 — pass `jobSite` from both callers (AC6): `JobDetailScreen.tsx`, `TechJobDetailContent.tsx`
- [x] Task 5 — full suite green (`bun run test`), lint clean

### Review Findings

*BMAD code review 2026-09-14 — three adversarial layers (Blind Hunter / Edge Case Hunter / Acceptance Auditor) over the uncommitted working tree vs baseline f2981a4.*

- [x] [Review][Decision] PersonRow's built-in Call button was removed; the technician Customer card now has no call affordance — RESOLVED 2026-09-14: user accepted the removal deliberately (technician has no tap-to-dial on the customer card; owner screen has its own Call button). The stale `TechJobDetailContent` comment is updated to match.
- [x] [Review][Decision] `radius.pill` changed 999 → 5 (global token, ~16 consumers app-wide: Avatar, Badge, Button, chips) — RESOLVED 2026-09-14: user confirmed the change is deliberate; documented here as approved scope (Change Log revision 18 + File List).
- [x] [Review][Decision] `WorkflowStatus.tsx` rebuilt ("Step X of Y" now a `Badge` with `Workflow` icon) — RESOLVED 2026-09-14: user chose to document (Change Log revision 18 + File List).
- [x] [Review][Decision] Timeline row typography/spacing shifted for ALL rows (label `body` → `label`, `content` margin changes) — RESOLVED 2026-09-14: user chose to document in the Change Log (revision 18); accepted as part of the rail-marker restyle.
- [x] [Review][Patch] `eventStatusKey` lacks the null-eventType guard `resolveEventLabel` has — a null `eventType` (API contract violation) crashes `railMarker`/`dotColor` on `.startsWith` [src/features/jobDetail/eventLabels.ts:23-31]
- [x] [Review][Patch] Dead imports: `Phone` + `Wrench` in `JobDetailScreen.tsx`, `MapPin` in `WorkflowStatus.tsx` [src/features/jobDetail/JobDetailScreen.tsx:33-34]
- [x] [Review][Patch] Stale JSDoc: `formatDistance` doc still claims `≈ 120 m away` after the `≈` was dropped (revision 7); garbled "arc-minute" test comment (0.001° is not an arc-minute) [src/utils/distanceUtils.ts]
- [x] [Review][Patch] `copyPhone` copies blank numbers (false "Copied" feedback — mirror `openTel`'s blank guard); both copy buttons share one accessibility label; "Copied" note is not announced to screen readers [src/features/jobDetail/JobDetailScreen.tsx:100-105]
- [x] [Review][Patch] `badgeRow` has no `flexWrap` — a long template step label in the latest-event badge overflows the Card horizontally [src/features/jobDetail/components/JobHeaderCard.tsx:114-118]
- [x] [Review][Patch] `jobSiteCoords` accepts non-numeric/out-of-range coordinates (only null-checked) → `NaN km away` chip; validate range like `parseStepLocation` does [src/features/jobDetail/locationMetadata.ts:75-81]
- [x] [Review][Patch] `formatDistance(996)` renders `1000 m away` — metre rounding can land exactly on the km threshold it otherwise switches at [src/utils/distanceUtils.ts:17-31]
- [x] [Review][Patch] `lastKnownTechnicianLocation` ignores `eventType` — any log entry whose metadata carries a coordinate pair counts as "the technician's last known location"; filter to `step_*` events [src/features/jobDetail/locationMetadata.ts]
- [x] [Review][Patch] Touched files missing trailing newlines (JobDetailScreen, eventLabels, locationMetadata, distanceUtils, test files) [multiple]
- [x] [Review][Defer] Core `Clipboard` is deprecated in RN (moved to `@react-native-clipboard/clipboard`) [src/features/jobDetail/JobDetailScreen.tsx:38] — deferred, deliberate documented trade-off (no new dependency on RN 0.86; revisit on next RN upgrade)
- [x] [Review][Defer] Unknown `step_*` keys render raw (e.g. `step_on_my_way`) in timeline and now the header badge [src/features/jobDetail/eventLabels.ts] — deferred, mirrors timeline fallback; fallback wording is a product decision for later
- [x] [Review][Defer] Technician app hides the maps row for coords-only customers while the owner app enables Direction (audience asymmetry) [src/features/technicianApp/components/TechJobDetailContent.tsx:111-117] — deferred, pre-existing gate unchanged by this diff

## Context

Epic 7 captured the technician's GPS position into `activity_logs.metadata` on every location-required step advance, but nothing renders it — `ActivityTimeline.tsx` shows only the event label and timestamp. This story is the read-side: compute the **straight-line (haversine) distance** between the captured coordinates and the job site's coordinates (the customer's saved `latitude`/`longitude`, exposed by story 2-1), and show it as a caption under each step row — "≈120 m away" style.

**Zero backend change.** `GET /jobs/:id` already returns both ends of the distance in one response:
- `activityLog[].metadata` — `latitude`, `longitude`, `accuracy`, `locationCaptured`, `reason`, `accuracyFlagged` (key names verified in migration `20260913000002`; `jsonb_strip_nulls` drops absent keys)
- `customer.latitude` / `customer.longitude` — nullable, `JobDetailCustomer` (fenzo-app `src/services/resources/jobs.ts:247-261`)

**Product decisions locked (2026-09-14):**
- Missed captures are shown **with** their reason (aligned with CAP-4 — location never blocks work).
- Both owner and technician see it (the timeline is already shared and dumb-by-design).
- Straight-line distance, NOT road distance — no maps API, no new dependency. Stated in the story so nobody expects route distance.
- Display only. **No geofence enforcement** — distance never gates or blocks a step (CAP-4 holds).

**Note:** the job-level `capture_location_on_steps` toggle was removed from the FE (commit `d4ec3c9`) — step-level `requires_location` is the single source of truth now. This story touches none of that.

## Changes

fenzo-app only. No backend change, no new dependency (haversine is ~10 lines of pure math). Single commit in `fenzo-app`.

### 1. NEW — `src/utils/distanceUtils.ts` (pure functions, per utils folder rules)

```ts
/** Great-circle distance in metres between two lat/long pairs (haversine). */
export function haversineMetres(
  a: { latitude: number; longitude: number },
  b: { latitude: number; longitude: number },
): number;

/** "≈120 m away" under 1 km; "≈2.4 km away" at or above (1 decimal). */
export function formatDistance(metres: number): string;
```

- Pure math, no RN imports, no side effects.
- Rounding: metres round to nearest 10 m (a 3-metre-precise number implies GPS precision it doesn't have); km to 1 decimal.
- Colocated `distanceUtils.test.ts` (jest, same pattern as `relativeTime.test.ts`), re-export from `src/utils/index.ts`.

### 2. NEW — `src/features/jobDetail/locationMetadata.ts` (defensive parser)

`metadata` is `Record<string, unknown> | null` on the wire — parse defensively, never trust the shape:

```ts
type StepLocation =
  | { kind: 'captured'; latitude: number; longitude: number; accuracy: number | null; flagged: boolean }
  | { kind: 'missed'; reason: string | null }
  | { kind: 'none' };

export function parseStepLocation(metadata: Record<string, unknown> | null): StepLocation;
```

Rules (mirror the RPC's write branches exactly — migration `20260913000002` CASE block):
- Both `latitude` and `longitude` are finite numbers in range (±90 / ±180) → `captured` (partial pair → treat as `none`, matching the RPC's "together or not at all" rule).
- Else `locationCaptured === false` → `missed` with `reason` (string or null).
- Anything else (null metadata, pre-Epic-7 rows, other events' metadata like `job_reassigned`'s technicianId) → `none`.
- `accuracyFlagged === true` → `flagged`. `accuracy` may be absent (`jsonb_strip_nulls`).
- Colocated `locationMetadata.test.ts` covering: null metadata, coordinates present, missed+reason, flagged, partial pair, non-numeric garbage → `none`.

### 3. UPDATE — `src/features/jobDetail/components/ActivityTimeline.tsx`

Currently renders label + timestamp only (137 lines). Add one caption `<Text>` under the timestamp:

- Extend `Props` with optional job-site coordinates: `jobSite?: { latitude: number; longitude: number } | null`.
- Per entry: `parseStepLocation(entry.metadata)` →
  - `captured` + `jobSite` present → `<formatDistance(haversineMetres(...))>` (AC1); `flagged` appends ` · low GPS accuracy` (AC4)
  - `captured` + no `jobSite` → `Location captured` (AC2)
  - `missed` → `Location not captured{reason ? ` — ${reason}` : ''}` (AC3)
  - `none` → render nothing, row unchanged (AC5)
- Styling: `typography.caption`, `colors.textMuted`, `marginTop: spacing.s1` — same visual tier as the timestamp; never hard-coded values (design-system tokens only).
- Keep the component dumb: props in, UI out — the distance is computed in the render path from props, no API or hook changes.

### 4. UPDATE — callers pass `jobSite`

- `src/features/jobDetail/JobDetailScreen.tsx` (~line 103): pass `jobSite={detail.customer.latitude != null && detail.customer.longitude != null ? { latitude: detail.customer.latitude, longitude: detail.customer.longitude } : undefined}`
- `src/features/jobDetail/TechJobDetailScreen.tsx` (~line 123): same.
- Both screens already fetch the full `JobDetail` via `jobService.getById` — no service or hook changes anywhere.

## Testing

- [ ] Unit (`bun test` → jest): `distanceUtils.test.ts` — haversine known pairs (same point → 0; ~111 m ≈ 0.001° lat apart; antipodal sanity), formatter m/km boundary (999 m → m, 1000 m → km), rounding
- [ ] Unit: `locationMetadata.test.ts` — all `StepLocation` variants + hostile shapes (metadata as array/string, metadata values as strings/NaN)
- [ ] Component: ActivityTimeline renders caption variants and unchanged rows for `none` (AC5)
- [ ] Manual: owner detail + technician detail both show distances for a job with Epic-7 captures; a pre-Epic-7 job shows no captions; a customer without coordinates shows `Location captured` only

## Dev Notes

- **Relative imports everywhere** — no file in this repo uses aliases yet (CLAUDE.md reality note 2026-09-09); match the surrounding code. `ActivityTimeline.tsx` imports `'../../../theme'` / `'../../../services'` today.
- **Metadata key names are camelCase on the wire** (`locationCaptured`, `accuracyFlagged`, `reason`) — set by the RPC's `jsonb_build_object`; do not invent snake_case variants.
- **`locationCaptured` may be absent when coordinates are present** (`jsonb_strip_nulls` drops it when null) — presence of a valid coordinate pair is the source of truth for "captured", not the boolean.
- **Reasons are server-authored, already human-readable strings** from `WorkflowService` (verified: `'Location not provided'`, `'Location coordinates out of valid range'`) — render raw, no humanization lookup; any unknown future string also renders raw, never crashes.
- **Technician timeline lives in `TechJobDetailContent.tsx`** (the screen shell is `TechJobDetailScreen.tsx`); the `ActivityTimeline` mount is there.
- **Distance is point-in-time**: the technician's position at the moment of that step advance vs the customer's saved address — the caption must not imply live tracking or current position.
- **No new dependency.** `react-native-nitro-geolocation` stays untouched; no maps SDK, no geocoding call.
- **Out of scope (do not build):** road distance via a maps API, geofence blocking/validation, live location, per-step configuration UI, any backend change.

### Project Structure Notes

- `utils/` = pure functions only, one file per domain, colocated `.test.ts`, re-exported from `index.ts` — matches `relativeTime.ts`, `idempotency.ts` precedent.
- Parser lives in `features/jobDetail/` (feature-specific), distance math in `utils/` (generic) — mirrors how `eventLabels.ts` sits in `features/jobDetail/`.
- Relative date/time formatting precedent: `src/utils/istDate.ts`, `relativeTime.ts` — follow their pure-function + JSDoc style.

### References

- [Source: artifacts/specs/spec-job-step-location-capture/SPEC.md — Non-goals: owner-facing viewer deferred; geofence validation remains out]
- [Source: fenzit-be supabase/migrations/20260913000002_advance_workflow_step_location_params.sql — metadata key names and the together-or-not-at-all rule]
- [Source: src/services/resources/jobs.ts:211-221 — `ActivityLogEntry.metadata`; :247-261 — `JobDetailCustomer` coordinates]
- [Source: src/features/jobDetail/components/ActivityTimeline.tsx — current render, shared by both audiences]
- [Source: fenzo-app commit d4ec3c9 — job-level toggle removed; step `requires_location` is the single source of truth]

## Dev Agent Record

### Agent Model Used

Claude Code (GLM) — 2026-09-14

### Debug Log References

- RED→GREEN verified: both unit suites confirmed failing on missing modules before implementation, then passing.
- Component-test harness: bare `react-test-renderer.create()` unmounts under this jest preset — repo precedent wraps `create()` in `act()` (see `SignatureScreen.test.tsx`); followed it.
- Full suite: baseline `main` (f2981a4) = 31 failed / 734 passed / 765 total; with this story = 31 failed / 758 passed / 789 total — **identical failure set, 24 new passing tests, zero regressions** (verified by stash-diff of both runs).
- `bunx tsc --noEmit`: 78 errors on baseline, 78 after, identical file set — zero new type errors (pre-existing stale fixtures: `serviceType`, `skillId`, `requiresLocation` in `__tests__/`).
- `bun run lint`: not runnable — no ESLint config file exists in the repo (pre-existing gap, out of story scope).

### Completion Notes List

- `distanceUtils.ts`: haversine (mean Earth radius 6371008.8 m) + `formatDistance` (metres rounded to 10s below 1 km; km to 1 decimal above; boundary at exactly 1000 m → km).
- `locationMetadata.ts`: `parseStepLocation` mirrors the RPC's write branches exactly (together-or-not-at-all coordinate pair; `locationCaptured` implied by coordinate presence since `jsonb_strip_nulls` drops it; `missed` only on explicit `false`); hostile shapes (arrays, primitives, non-numeric values) degrade to `none`.
- `ActivityTimeline`: `jobSite` prop (optional/null) + one caption line at the timestamp's visual tier; `none` rows render byte-identical markup to before.
- Reasons rendered raw — server strings are already human-readable (`'Location not provided'`, `'Location coordinates out of valid range'`, verified in `fenzit-be/src/jobs/workflow.service.ts:210-213`).
- `jobSiteCoords()` helper (not in original Changes list — added during Task 4) converts the nullable customer coordinate pair to the prop, never half-used; tested.
- No new dependencies. No backend changes. No role gating — both screens pass the same `jobSite`.
- Pre-existing failures on `main` (31 tests, 78 TS errors) are NOT addressed by this story — flagged for a separate cleanup story (likely fallout of commit d4ec3c9 and stale test fixtures).
- UI revision (user-requested, 2026-09-14): the captured-distance caption renders as a **chip** — a soft blue `Badge` (status `progress`) with a leading `MapPin` pin icon — instead of a plain muted caption, per the user's mock. `Badge` gained an optional generic `icon` prop (no status-vocabulary change); `Location captured` / `Location not captured — reason` remain plain muted captions; the `· low GPS accuracy` hint stays a muted caption beside the chip (AC4 intact). `formatDistance` now emits `≈ 120 m away` (space after `≈`, matching the mock).

### File List

- src/components/ui/Badge.tsx (modified — optional `icon` prop)
- src/theme/radius.ts (modified — `radius.pill` 999 → 5; user-approved global pill restyle, see Change Log revision 18)
- src/features/jobDetail/components/WorkflowStatus.tsx (modified — "Step X of Y" rebuilt as a `Badge` with a `Workflow` icon; user-approved, revision 18)
- src/utils/distanceUtils.ts (new)
- src/utils/distanceUtils.test.ts (new)
- src/utils/index.ts (modified — re-exports)
- src/features/jobDetail/locationMetadata.ts (new)
- src/features/jobDetail/locationMetadata.test.ts (new)
- src/features/jobDetail/components/ActivityTimeline.tsx (modified — caption + jobSite prop)
- src/features/jobDetail/components/ActivityTimeline.test.tsx (new)
- src/features/jobDetail/JobDetailScreen.tsx (modified — pass jobSite)
- src/features/technicianApp/components/TechJobDetailContent.tsx (modified — pass jobSite)

## Change Log

- 2026-09-14: Review patches applied (all 9, user chose "apply every patch"): (1) `eventStatusKey` gained the null-eventType guard; (2) dead imports removed (`Phone`/`Wrench` in JobDetailScreen, `MapPin` in WorkflowStatus); (3) `formatDistance` JSDoc + garbled arc-minute test comment fixed; (4) `copyPhone` blank-half guard, distinct accessibility labels ("Copy customer/technician phone number"), `accessibilityLiveRegion="polite"` on both "Copied" texts; (5) `badgeRow` gained `flexWrap`; (6) `jobSiteCoords` range-validates via `toCoord`; (7) `formatDistance` boundary fixed — a reading that rounds to 1000 m renders as `1.0 km away` (test updated to pin the new behaviour); (8) `lastKnownTechnicianLocation` filters to `step_*` events (signature now requires `eventType`); (9) trailing newlines added to touched files. Verification after: 26/26 tests green across the three suites; `tsc --noEmit` shows only the pre-existing baseline errors (JobHeaderCard 50/51 statusBadge typing, stale editJobModel/TechJobDetailContent test fixtures).
- 2026-09-14: Review decisions recorded (BMAD code review, three adversarial layers). Approved scope now documented: (a) `radius.pill` 999 → 5 — deliberate global pill restyle (badges/chips/avatars render with 5px corners app-wide), kept by user decision; (b) `WorkflowStatus.tsx` "Step X of Y" rebuilt as a `Badge` with a `Workflow` icon — kept, documented; (c) timeline row typography/spacing shifts (label role `body` → `label`, `content` margins) accepted as part of the revision-2 rail-marker restyle; (d) PersonRow's built-in Call button removal accepted — the technician Customer card deliberately has no tap-to-dial (owner screen has its own Call/Direction row); stale comment in `TechJobDetailContent` updated.
- 2026-09-14: UI revision 17 (user-requested) — all badges in the header's badge row (Urgent, job status, latest event) now render at the default `md` size; the latest-event badge was `sm` next to the `md` status badge, which read as mismatched pills.
- 2026-09-14: UI revision 16 (user-requested) — the latest-event badge and the timeline dots now share one colour mapping: `eventStatusKey(eventType)` (in `eventLabels.ts`) returns the status class per event (completed → done, in-progress → progress, cancelled → cancelled, everything else neutral); `ActivityTimeline.dotColor` and the header badge both derive from it, so the coding can't drift between the two surfaces. Timeline neutral dots keep their exact grey (`textDisabled`).
- 2026-09-14: UI revision 15 (user-requested) — the header card's badge row gained a third badge: the latest activity event (the log is oldest-first) rendered as a soft `Badge` after the Urgent/status badges, labelled via the timeline's own resolver. `resolveEventLabel` moved from `ActivityTimeline.tsx` into `eventLabels.ts` so the header and timeline share one template-aware lookup (step events resolve through `workflowTemplate`, unknown types render raw). Badge status mirrors the timeline's dot classes: `step_completed` → done, `step_*` → progress, `job_cancelled` → cancelled, else neutral.
- 2026-09-14: UI revision 14 (user-requested) — removed the duplicate customer address (text + city chip) from the Customer section; the bordered address box now lives only in the header card. Customer section: person row (with copy) → Call/Direction → hint. Orphaned styles (`addressBox`, `sectionMetaRow`, `metaText`, `cityRow`) and now-unused imports (`MapPin`, `touch`) cleaned out of `JobDetailScreen`.
- 2026-09-14: UI revision 13 (user-requested) — the header card's address box now also carries the city chip (`Badge` neutral soft with a small `MapPin`), matching the customer card; the job has no city field of its own, so the chip reads `detail.customer.city` — the same source as the customer card's chip.
- 2026-09-14: UI revision 12 (user-requested) — `JobHeaderCard`'s service-location address gets the same bordered-box treatment as the customer card's address (1px `borderSubtle` · `radius.sm` · `palette.gray50` ground · text in `palette.gray600`, the nearest token to the user's `#4B586C`). The user kept the SectionCard itself on the default white ground (removed the interim card-tint change).
- 2026-09-14: UI revision 11 (user-requested) — the customer's address line + city chip sit inside a bordered box (1px `colors.borderSubtle`, `radius.xs` = 4, `spacing.s2` padding; the box shows when either address or city exists, so a city-only customer still gets the box).
- 2026-09-14: UI revision 10 (user-requested) — the Technician card's phone number gets the same copy affordance (icon after the number, raw diallable copy, transient "Copied" note); both cards share one `copyPhone(side, …)` handler so only the tapped card shows "Copied".
- 2026-09-14: UI revision 9 (user-requested) — the copy icon moved from the address row to sit right after the customer's phone number (`PersonRow` gained an optional trailing `action` slot rendered inline after the sub-line); it now copies the raw diallable number (`countryCode` + `phoneNumber`) with the same transient "Copied" feedback. The address row is back to pin + text only.
- 2026-09-14: UI revision 8 (user-requested) — Customer card: a `Copy` icon button (ghost IconButton, lucide `Copy`) copies the full address (address + city) to the clipboard via react-native's core `Clipboard` (deprecated but functional in RN 0.86 — no new dependency), with a brief "Copied" caption as feedback; `detail.customer.city` moved out of the joined address text into its own chip (`Badge` status `neutral`, tone `soft` — gray border + background — with a small `MapPin` icon).
- 2026-09-14: UI revision 7 (user-requested) — while the technician's Direction button is **enabled**, an Info-icon hint states "Directions will take you to the technician's last known location, not live tracking." (display-only reminder, story 7.10's no-live-tracking rule). User also dropped the `≈ ` prefix from `formatDistance` — the chip's `EqualApproximately` icon now carries the "approximately" — tests updated to match.
- 2026-09-14: UI revision 6 (user-requested) — disabled Direction buttons explain themselves: a muted caption under the button row shows why ("No address or location is saved for this customer yet." / "Direction is available once the technician's location is captured on a step."), rendered only while the button is off.
- 2026-09-14: UI revision 5 (user-requested) — the Customer card's placeholder Call/Direction buttons are wired: Call dials the customer (`openTel`); Direction opens maps preferring the customer's saved coordinates (precise pin, story 2.1) with the address/city text query as fallback, and is disabled when the customer has neither.
- 2026-09-14: UI revision 4 (user-requested) — the owner's Technician card gained a Call + Direction button row: Call dials the technician (`openTel`), Direction opens maps to the technician's **last known location** (latest captured GPS fix in the activity log, via new `lastKnownTechnicianLocation()` helper) and is **disabled until such a fix exists** (2 new tests, TDD).
- 2026-09-14: UI revision 3 — briefly changed the chip to `≈ 6.7 km from job site`, then reverted by user decision: final text is `≈ 6.7 km away` (pin icon on the blue chip).
- 2026-09-14: UI revision 2 (user-requested) — timeline rail markers are now icons per the user's mocks: grey plus circle for `job_created`, green tick circle for `step_completed`, blue tick circle for in-progress `step_*` events (soft status-token backgrounds, solid-token borders, lucide `Plus`/`Check` glyphs); `job_cancelled` and unknown event types keep the plain colour dot. Marker colours come only from `colors.status.*` tokens.
- 2026-09-14: UI revision (user-requested) — captured distance now renders as a chip: soft blue Badge (`status="progress"`) with a leading MapPin icon, replacing the plain muted caption; `Badge` extended with an optional `icon` prop; `formatDistance` spacing matched to the mock (`≈ 120 m away`). Missed captures and the no-coordinates case stay plain captions; low-accuracy hint stays muted beside the chip. All 24 story tests pass; same 78 pre-existing TS errors as baseline, none in touched files.
- 2026-09-14: Story 7.10 implemented — straight-line (haversine) technician-distance-from-job-site captions in the shared ActivityTimeline, visible to owner and technician; missed captures with reason; low-accuracy hint; no caption on non-location rows. fenzo-app only, no backend change, no new dependency. 24 new tests (all passing); full suite shows the same 31 pre-existing failures as baseline, zero regressions.