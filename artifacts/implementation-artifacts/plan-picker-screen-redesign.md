---
title: 'Map pin picker redesign — services-off and pinned states (per user mockups)'
type: 'feature'
ticket: ''
created: '2026-10-18'
status: 'done'
route: 'full'
route_source: 'auto'
review: 'bmad-build step-04 (3 lenses)'
review_source: ''
lenses_ran: [blind-hunter, edge-case-hunter, verification-gap]
review_loop_iteration: 0
baseline_revision: '49c2f08'
context: ['artifacts/planning-artifacts/ux-designs/ux-map-pin-picker-2026-10-18/DESIGN.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The map pin picker works correctly (services-off recovery shipped in 49c2f08) but presents it as plain text rows; the user supplied two mockups (services-off, pinned) with a clearer visual hierarchy — cards, state chips, primary/secondary action split, approx-area while off.

**Approach:** Presentation-layer redesign of `MapPinPickerScreen` + `PickerMapArea` + `PickerBottomCard` per DESIGN.md (the approved spec). The four-state machine, remediation ladder, copy semantics, and all behavioral test contracts are unchanged.

## Boundaries & Constraints

**Always:**
- UX-corrected copy (frozen decision): body reads "Turn on location in Settings so we can detect accurate doorstep coordinates." — never "permission" in the services-off card.
- Search = top bar; focus/submit opens the existing AddressPickerSheet (frozen decision — no inline dropdown).
- Office-mode RadiusStepper stays in the sheet between address area and Confirm (frozen decision).
- Theme tokens only (amber = scheduled family, success = success family) — no new colors; touch targets ≥ 44; accessibilityRole/labels on every new element.
- Approx. Area reverse-geocode runs on drag-settle even with services off (manual placement is first-class).

**Never:**
- No changes to `useLocateMe`/`deviceLocation` logic, the remediation ladder, verify-step flow, or navigation contracts.
- No inline search dropdown results; no header help button (deferred); no new dependencies.
- Do not break the existing picker test suites — behavior-level assertions (which buttons appear, what handlers fire, copy literals) stay true; restyle-only changes may update style-level assertions.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Services OFF, sheet | picker opens / probe fails | amber card (title + body per copy), [Turn on device location] primary, [Search or enter address manually] secondary; Approx. Area row shows reverse geocode of pin; NO generic error row | reverse-geocode failure → area row shows coordinate fallback or hides (never blocks) |
| Services OFF, map | same | crosshair puck + "⚠ Drag map to set manually" chip; chip hides while dragging, returns on settle | — |
| Pinned / healthy | services on, fix or manual settle | teardrop pin + "● Exact pin location" chip; "✓ PINNED LOCATION" + "Drag map to refine"; address card (bold name + address + Change); "Confirm location →" | — |
| Transient failure | timeout/unavailable with services on | existing error row (text + [Open settings] after 2 denials), restyled to card spacing — visually distinct from amber card | unchanged |
| Office mode | mode='office' | RadiusStepper between address area and Confirm; everything else identical | — |
| Search bar | tap/submit | opens AddressPickerSheet (existing sheet flow, unchanged) | — |

</frozen-after-approval>

## Code Map

- `src/features/attendance/offices/MapPinPickerScreen.tsx` — screen shell: header, sheet composition, `handleEnableServices`/`handleLocate`/`handleResolvedPlace` wiring, reverse geocode on settle (`:176-197` area), AppState re-probe (keep as-is)
- `src/features/attendance/offices/PickerMapArea.tsx` — map surface: search bar (new), state chip over pin, pin styles, "Use my current location" pill reposition; locate button currently `:104-112`
- `src/features/attendance/offices/PickerBottomCard.tsx` — sheet content: two-state layout per DESIGN.md; services-off block currently `:62-77`; generic row `:72-81`; RadiusStepper `:82-84`
- `src/components/ui/InlineNotice.tsx` — existing tones; the new amber card is a richer local composition (icon chip + title + body) built from theme tokens — extend or compose, do not alter existing tones
- `src/features/addressPicker/AddressPickerSheet.tsx` — unchanged; opened from search bar + Change + secondary button
- Tests: `MapPinPickerScreen.servicesOff.test.tsx`, `MapPinPickerScreen.customerPin.test.tsx`, `PickerBottomCard.test.tsx`, `useLocateMe.test.tsx` — update style-level assertions; keep all behavioral ones

## Tasks & Acceptance

**Execution:**
- [x] `PickerBottomCard.tsx` — two-state sheet per DESIGN.md (amber card w/ icon+title+body; Approx. Area row + Change; primary/secondary buttons; pinned chips + address card; Confirm →) — the core redesign
- [x] `PickerMapArea.tsx` — top search bar (opens sheet via new `onOpenSearch` prop), state chip over pin (drag-aware), crosshair puck for services-off, relocate pill bottom-right with glyph
- [x] `MapPinPickerScreen.tsx` — wire new props (search bar, approx-area reverse geocode incl. services-off settle, state flags); remove the old floating "Search address" pill
- [x] tests — update the three picker suites' style-level assertions; add: approx-area renders while services off; state chip text switches with services state; search-bar press opens sheet; office stepper still renders between address area and Confirm

**Acceptance Criteria:**
- Given services OFF, the picker sheet shows the amber card with the frozen copy, a working [Turn on device location] (existing ladder), [Search or enter address manually] (opens sheet), and Approx. Area for a manually dragged pin.
- Given services ON with a settled pin, the sheet shows PINNED LOCATION + address card + Confirm →, and the map shows the teardrop pin with the exact-pin chip.
- Given office mode, the RadiusStepper renders in the new sheet and still updates radius.
- All behavioral assertions from 49c2f08's suites still pass (state machine untouched).

## Implementation Notes

- Built by a previous agent session (zcode), resumed and verified 2026-10-18 in this session. Working tree uncommitted in fenzit-app on baseline 49c2f08: PickerBottomCard, PickerMapArea, MapPinPickerScreen + 3 picker test files (+ deviceLocation.test.ts untracked).
- Verified: `bunx tsc --noEmit` clean (fixed 2 test-only type errors in PickerBottomCard.test.tsx: BASE props), `bun run test` 250 suites / 3176 tests green.
- Device screenshots 11–17 in `location-services-off-verification-2026-10-18/` show the iterations; user's decisions made on-device superseded some frozen literals (see Plan Change Log).

- COMMITTED + PUSHED 2026-10-18: fenzit-app c9a3da9 (main). Status: done.

## Plan Change Log

- 2026-10-18 (on-device iteration, per screenshots 15–17): services-off card moved from amber to the red (cancelled) family; copy simplified to plain English — title "Your phone location is off", body "Please turn on location in your phone settings. This helps us find the correct place.", primary "Turn on location", row "Nearby area", chip text "Location set"/drag hint. Search is top-bar only (sheet no longer has a manual-search button). Frozen-block copy literals ("Device location is turned off", "Turn on device location", "Approx. Area", amber) are therefore historical; tests assert the shipped copy. TODO for user: confirm these deviations are intended.

## Review Triage Log

2026-10-18 — 3 lenses (blind-hunter, edge-case-hunter, verification-gap), diff vs 49c2f08. ~60 raw findings -> 9 patched, 3 deferred, 0 intent_gap/bad_spec, rest rejected after reading the code (severity assigned by me, not the reviewers).

**Patched (all verified; tsc clean, 250 suites / 3181 tests):**
1. Raw "lat, lng" fallback label was split at its comma into bold "12.97160" + muted "77.59460" (healthy state, failed geocode) -> card now treats a coordinate label as one value. Test added.
2. Empty-string reverse-geocode address rendered a blank row (`??` does not catch '') -> `||` in screen. Test added.
3. Locate pill accepted a second tap while locating (old Button blocked it) -> onPress disabled while `locating`. Test added.
4. State chip said "Exact location" over the "Map unavailable" panel -> chip hidden when `mapFailed`.
5. Hard-coded `borderRadius: 999` -> `radius.pill` token.
6. No screen-level test that "Change area" re-centres the map on the current pin -> added (local react-native-maps mock with animateToRegion spy).
7. No test that the chip hides while dragging and returns on settle -> added.
8-9. Stale docblocks / comments / test titles still said amber, "Approx. Area", "Turn on device location", "Search or enter address manually", "Exact pin location" -> updated in card, map area, screen, and both test files.
(Mutation check: undoing fixes 1 and 3 turns the new tests red.)

**Deferred (-> deferred-work.md):** reduce-motion handling for the infinite ripple loop; services-off flag derives from errorKind (baseline 49c2f08 design — a later transient error can mask it).

**User decisions after triage (2026-10-18):** (a) map chip warning icon now red (cancelled family) to match the card; (b) files split to honour the ~300-line rule — `PickerCentrePin.tsx` (pin/puck/chip overlay + animations, from PickerMapArea 411 -> 226) and `ServicesOffCard.tsx` (red card + announcement, from PickerBottomCard 364 -> 284). Behaviour unchanged; tsc clean, 250 suites / 3181 tests green. The size deferral is therefore closed.

**Rejected (examples):** stale address beside spinner (momentary), "LOCATION SET" overclaim and red-vs-amber (design/user decisions), onEnableServices undefined (screen always passes it), a11y role "search" (valid RN role), speculative deviceLocation test gaps, magic-number sizes (icon-chip dimensions, not DS scale values), Change-link no-op when map unavailable (low).

**Later UI iteration (2026-10-18, user-directed on device screenshots):** removed the Nearby-area "Change" link, the "ACTION NEEDED" badge, the "LOCATION SET" chip and "Move map to adjust" text; address allows 3 lines; the blue teardrop pin is gone — the pulsing dot is the only pin in every state; chip is "Drag map to set pin" in both states (green dot healthy, amber dot services-off, one-shot slow bounce, reduce-motion respected); locate pill renamed "Use current location"; new amber `LocationOffBanner` with a [Turn on] pill inside the address-search sheet — Turn on keeps the sheet open, the fix is captured quietly and the pin moves only when the sheet closes, and a picked/typed address always wins (epoch guard). `MapPinPickerScreen` split into `usePickerLocate`, `useReverseAddress`, `buildCustomerPick` (464 -> 315 lines).

**Small BMAD review of that iteration:** 4 patched (reduce-motion promise rejection, empty-address `||` in the customer payload, banner truncation, race tests + `buildCustomerPick` unit tests); deferred: late fix overriding a manual drag after the sheet closed, no in-sheet feedback when the quiet locate fails, double-tap on Turn on, chip bounce replaying on every drag settle; ~25 dismissed. Full suite 251 suites / 3191 tests, tsc clean. Pixel 6 check of this iteration still pending.

## Design Notes

Pin-style swap and chip copy are state-driven from ONE prop (`servicesOff`) already flowing into the bottom card — lift it to the screen level and pass to both surfaces so map and sheet can never disagree.

## Verification

**Commands:**
- `bun run test` -- expected: all suites green (behavioral assertions intact)
- `bun run typecheck` if configured, else `bunx tsc --noEmit` on changed files

**Manual (device, after build):**
- Android: services off → picker shows amber card + crosshair puck; drag pin → Approx. Area updates; [Turn on device location] → dialog → auto re-locate → pinned state appears
- Office mode: stepper renders and works; customer mode matches mockups
