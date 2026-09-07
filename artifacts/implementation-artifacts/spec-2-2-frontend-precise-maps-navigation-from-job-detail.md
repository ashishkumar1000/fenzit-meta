---
title: 'Frontend — Precise maps navigation from job detail'
type: 'feature'
created: '2026-09-07'
status: 'ready-for-dev'
review_loop_iteration: 0
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
- Coordinate deep link forms (AC-fixed): iOS `maps:{lat},{lng}?q={lat},{lng}`, Android `geo:{lat},{lng}?q={lat},{lng}` — plain numeric interpolation, no rounding, no `encodeURIComponent` (numbers need no escaping; the `0,0` prefix is deliberately dropped — the device centers on the point itself, not a search box). Text-fallback URL forms stay byte-identical to today.
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
| Customer with coordinates | Job whose customer has non-null `latitude` + `longitude` (Story 2.1) | Maps row opens `maps:{lat},{lng}?q={lat},{lng}` (iOS) / `geo:{lat},{lng}?q={lat},{lng}` (Android); row visually identical to today | `openURL` rejection → `console.warn`, no throw |
| Customer without coordinates | Both `null` (legacy customer, or free-text creation) | Exact today's fallback: `maps:0,0?q=<address, city>` / `geo:0,0?q=...` text query — unchanged bytes | Same as today |
| Half-present coordinates | Only `latitude` or only `longitude` non-null (allowed by Story 1.3) | Not usable → text-query fallback, identical to the null case; never a fabricated or zero-padded coordinate | N/A |
| No address text, coordinates present | `customer.address` null (row not rendered) | Row stays unrendered — existing gate unchanged; coordinates alone never summon the row | N/A |
| Existing row behaviors | Back nav, other cards, PersonRow phone affordance | Byte-identical rendering; only the URL string passed to `Linking.openURL` differs | N/A |
| `Linking` unavailable / rejects | iOS query rejection, no maps app | Swallowed silently per the file's existing contract (`canOpenURL`-style quiet give-up is not required here — today's `openMaps` doesn't `canOpenURL` and that stays the case) | `console.warn` |

</frozen-after-approval>

## Code Map

- `src/utils/linking.ts:40-55` -- `openMaps`: add optional third `coords` param (inline `{ latitude: number | null; longitude: number | null }` type); usable-coords branch builds the coordinate URL (prefix `maps:`/`geo:` per `Platform.select` + `{lat},{lng}?q={lat},{lng}`), else falls through to the existing text-query logic unchanged; update the function doc-comment to describe both modes
- `src/services/resources/jobs.ts:212-220` -- `JobDetailCustomer`: add `latitude: number | null; longitude: number | null;` with the same "null when…" doc-comment style as `address`/`city`
- `src/features/technicianApp/components/TechJobDetailContent.tsx:126` -- maps row `onPress`: pass `{ latitude: detail.customer.latitude, longitude: detail.customer.longitude }` as `openMaps`'s third argument; nothing else in the component changes
- `src/utils/linking.test.ts` (new) -- unit tests with `Linking` mocked: coordinate URL per platform, null-coords text URL, half-present-coords fallback, blank-everything no-op; `openTel` contract pinned too (cheap while the mock is up)
- `src/features/technicianApp/components/TechJobDetailContent.test.tsx` -- extend: press the maps row with a coordinates-bearing fixture → `openURL` received the coordinate URL; press with null coords → the exact text-query URL; fixture gains the two new fields
- Reference: `workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts` -- Story 2.1's response shape this story mirrors (do not touch; already merged)
- Reference: `artifacts/implementation-artifacts/spec-2-1-backend-expose-customer-coordinates-in-job-detail-response.md` -- the backend contract (field names, nullability, always-present keys)

## Tasks & Acceptance

**Execution:**
- [ ] `src/utils/linking.ts` -- `openMaps` coordinate branch + optional `coords` param; doc-comment updated
- [ ] `src/utils/linking.test.ts` -- new unit suite for `openMaps` (both modes + fallbacks) and `openTel` contract
- [ ] `src/services/resources/jobs.ts` -- `JobDetailCustomer` gains the two nullable fields
- [ ] `src/features/technicianApp/components/TechJobDetailContent.tsx` -- pass coordinates through on the maps row
- [ ] `src/features/technicianApp/components/TechJobDetailContent.test.tsx` -- fixture + press-the-row assertions for both URL modes

**Acceptance Criteria:**
- Given a job whose customer has saved coordinates, when the technician taps the maps row, then `openURL` is called with `maps:{lat},{lng}?q={lat},{lng}` (iOS) / `geo:{lat},{lng}?q={lat},{lng}` (Android)
- Given a customer with no (or half-present) coordinates, when the row is tapped, then `openURL` is called with exactly today's `maps:0,0?q=...` / `geo:0,0?q=...` text query — unchanged bytes
- Given either case, the row renders identically — no visual difference, no badge (UX-DR6)
- Given any other `openMaps`/`openTel` consumer, the signatures are backward-compatible (new param optional) and their behavior is unchanged

## Design Notes

- The "usable coordinates" rule (both non-null) lives inside `openMaps`, not the call site — one rule, one home; callers can't half-use it.
- No `encodeURIComponent` on the coordinate branch is deliberate: lat/lng interpolate to `[0-9.+-]` only. The text branch keeps its encoding as today.
- `openMaps` keeps swallowing its own failures — a rejected maps URL must never break a render-only row (file-level convention, documented at the top of `linking.ts`).
- Cross-repo ordering: Story 2.1 (`fenzit-be`, additive) already merged/deploys first; this story (`fenzo-app`) consumes the field. The FE type treats both fields as always-present-but-nullable, mirroring the backend's stable shape.
- Test note from the repo: jest runs via `bun run test` (never bare `bun test` — RN Flow types break it); add `--watchman=false` if watchman is sandbox-blocked.

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